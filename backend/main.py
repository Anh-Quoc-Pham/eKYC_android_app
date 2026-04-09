from __future__ import annotations

from collections import defaultdict, deque
import hashlib
import sqlite3
from threading import Lock
import time
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request, status
from pydantic import BaseModel, Field
from starlette.responses import JSONResponse

# RFC 3526 - 2048-bit MODP Group prime.
_P_HEX = (
    "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E08"
    "8A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD"
    "3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E"
    "7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899F"
    "A5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF05"
    "98DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C"
    "62F356208552BB9ED529077096966D670C354E4ABC9804F174"
    "6C08CA18217C32905E462E36CE3BE39E772C180E86039B2783"
    "A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497C"
    "EA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF"
)

P = int(_P_HEX, 16)
Q = (P - 1) // 2
G = 4

DB_PATH = Path(__file__).resolve().parent / "ekyc_phase3.db"

VERIFY_RATE_LIMIT_MAX_REQUESTS = 30
VERIFY_RATE_LIMIT_WINDOW_SECONDS = 60

_verify_rate_buckets: dict[str, deque[float]] = defaultdict(deque)
_verify_rate_lock = Lock()

app = FastAPI(
    title="eKYC Phase 3 ZKP Backend",
    version="1.0.0",
    description="Privacy-first backend with Schnorr proof verification",
)


class EnrollRequest(BaseModel):
    id_hash: str = Field(..., min_length=64, max_length=64)
    encrypted_pii: str = Field(..., min_length=8)
    public_key: str = Field(..., min_length=1)


class SchnorrProof(BaseModel):
    commitment: str = Field(..., min_length=1)
    challenge: str = Field(..., min_length=1)
    response: str = Field(..., min_length=1)
    session_nonce: str = Field(..., min_length=8, max_length=128)


class VerifyRequest(BaseModel):
    id_hash: str = Field(..., min_length=64, max_length=64)
    encrypted_pii: str = Field(..., min_length=8)
    public_key: str | None = None
    proof: SchnorrProof


def _get_connection() -> sqlite3.Connection:
    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON;")
    return connection


def _init_db() -> None:
    with _get_connection() as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS enrollments (
                id_hash TEXT PRIMARY KEY,
                encrypted_pii TEXT NOT NULL,
                public_key TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS used_nonces (
                id_hash TEXT NOT NULL,
                session_nonce TEXT NOT NULL,
                used_at INTEGER NOT NULL,
                PRIMARY KEY (id_hash, session_nonce),
                FOREIGN KEY (id_hash) REFERENCES enrollments(id_hash) ON DELETE CASCADE
            );
            """
        )


@app.on_event("startup")
def startup_event() -> None:
    _init_db()


def _is_valid_hex_sha256(value: str) -> bool:
    if len(value) != 64:
        return False
    lowered = value.lower()
    return all(char in "0123456789abcdef" for char in lowered)


def _parse_positive_int(raw_value: str, field_name: str) -> int:
    try:
        parsed = int(raw_value)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{field_name} phải là số nguyên dương.",
        ) from exc

    if parsed <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{field_name} phải lớn hơn 0.",
        )

    return parsed


def _is_subgroup_element(value: int) -> bool:
    if value <= 1 or value >= P:
        return False
    return pow(value, Q, P) == 1


def _compute_challenge(id_hash: str, session_nonce: str, commitment: int) -> int:
    payload = f"{id_hash}|{session_nonce}|{commitment}".encode("utf-8")
    digest = hashlib.sha256(payload).digest()
    return (int.from_bytes(digest, "big") % (Q - 1)) + 1


@app.middleware("http")
async def verify_rate_limit_middleware(request: Request, call_next):
    if request.url.path == "/verify":
        client_host = request.client.host if request.client else "unknown"
        bucket_key = f"{client_host}:{request.url.path}"
        now = time.time()

        with _verify_rate_lock:
            bucket = _verify_rate_buckets[bucket_key]

            while bucket and now - bucket[0] > VERIFY_RATE_LIMIT_WINDOW_SECONDS:
                bucket.popleft()

            if len(bucket) >= VERIFY_RATE_LIMIT_MAX_REQUESTS:
                return JSONResponse(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    content={
                        "verified": False,
                        "reason": "rate_limited",
                        "detail": "Too many verify attempts. Please retry later.",
                    },
                    headers={"Retry-After": str(VERIFY_RATE_LIMIT_WINDOW_SECONDS)},
                )

            bucket.append(now)

    return await call_next(request)


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/enroll")
def enroll(request: EnrollRequest) -> dict[str, str | int]:
    id_hash = request.id_hash.lower()
    if not _is_valid_hex_sha256(id_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="id_hash phải là SHA-256 hex (64 ký tự).",
        )

    public_key = _parse_positive_int(request.public_key, "public_key")
    if not _is_subgroup_element(public_key):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="public_key không hợp lệ trong nhóm Schnorr.",
        )

    now = int(time.time())
    with _get_connection() as connection:
        connection.execute(
            """
            INSERT INTO enrollments (id_hash, encrypted_pii, public_key, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id_hash) DO UPDATE SET
                encrypted_pii = excluded.encrypted_pii,
                public_key = excluded.public_key,
                updated_at = excluded.updated_at;
            """,
            (id_hash, request.encrypted_pii, str(public_key), now, now),
        )

    return {
        "status": "enrolled",
        "id_hash": id_hash,
        "updated_at": now,
    }


@app.post("/verify")
def verify(request: VerifyRequest) -> dict[str, bool | str | float | int]:
    id_hash = request.id_hash.lower()
    if not _is_valid_hex_sha256(id_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="id_hash phải là SHA-256 hex (64 ký tự).",
        )

    proof = request.proof
    commitment = _parse_positive_int(proof.commitment, "proof.commitment")
    challenge = _parse_positive_int(proof.challenge, "proof.challenge")
    response = _parse_positive_int(proof.response, "proof.response")

    if not _is_subgroup_element(commitment):
        return {
            "verified": False,
            "reason": "commitment_not_in_subgroup",
            "score": 0.0,
            "server_time": int(time.time()),
        }

    if challenge >= Q or response >= Q:
        return {
            "verified": False,
            "reason": "proof_out_of_range",
            "score": 0.0,
            "server_time": int(time.time()),
        }

    with _get_connection() as connection:
        enrollment_row = connection.execute(
            "SELECT id_hash, encrypted_pii, public_key FROM enrollments WHERE id_hash = ?",
            (id_hash,),
        ).fetchone()

        if enrollment_row is None:
            return {
                "verified": False,
                "reason": "not_enrolled",
                "score": 0.0,
                "server_time": int(time.time()),
            }

        stored_public_key = int(enrollment_row["public_key"])

        if request.public_key is not None:
            claimed_public_key = _parse_positive_int(request.public_key, "public_key")
            if claimed_public_key != stored_public_key:
                return {
                    "verified": False,
                    "reason": "public_key_mismatch",
                    "score": 0.0,
                    "server_time": int(time.time()),
                }

        replay_row = connection.execute(
            "SELECT 1 FROM used_nonces WHERE id_hash = ? AND session_nonce = ?",
            (id_hash, proof.session_nonce),
        ).fetchone()
        if replay_row is not None:
            return {
                "verified": False,
                "reason": "replay_detected",
                "score": 0.0,
                "server_time": int(time.time()),
            }

        expected_challenge = _compute_challenge(
            id_hash=id_hash,
            session_nonce=proof.session_nonce,
            commitment=commitment,
        )
        if challenge != expected_challenge:
            return {
                "verified": False,
                "reason": "challenge_mismatch",
                "score": 0.0,
                "server_time": int(time.time()),
            }

        lhs = pow(G, response, P)
        rhs = (commitment * pow(stored_public_key, challenge, P)) % P

        is_verified = lhs == rhs
        verification_score = 1.0 if is_verified else 0.0

        if is_verified:
            now = int(time.time())
            connection.execute(
                "INSERT INTO used_nonces (id_hash, session_nonce, used_at) VALUES (?, ?, ?)",
                (id_hash, proof.session_nonce, now),
            )
            connection.execute(
                "UPDATE enrollments SET encrypted_pii = ?, updated_at = ? WHERE id_hash = ?",
                (request.encrypted_pii, now, id_hash),
            )

        return {
            "verified": is_verified,
            "reason": "ok" if is_verified else "equation_failed",
            "score": verification_score,
            "server_time": int(time.time()),
        }

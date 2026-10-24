from dataclasses import dataclass

import jwt

from .config import Membership, Settings


class AuthError(Exception):
    pass


@dataclass(frozen=True)
class Principal:
    subject: str
    membership: Membership


class Authenticator:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.local_key = settings.local_public_key.read_text() if settings.local_public_key else None
        self.jwks = None if self.local_key else jwt.PyJWKClient(
            settings.issuer.rstrip("/") + "/.well-known/jwks.json", cache_keys=True, lifespan=300,
            timeout=5)

    def verify(self, authorization: str | None) -> Principal:
        if not authorization or not authorization.startswith("Bearer "):
            raise AuthError("A valid access token is required")
        token = authorization[7:]
        if len(token) > 16000:
            raise AuthError("Invalid access token")
        try:
            key = self.local_key or self.jwks.get_signing_key_from_jwt(token).key
            claims = jwt.decode(token, key, algorithms=["RS256"], issuer=self.settings.issuer,
                                options={"verify_aud": False,
                                         "require": ["exp", "iat", "sub", "iss", "token_use", "client_id"]},
                                leeway=5)
            if claims["token_use"] != "access" or claims["client_id"] != self.settings.client_id:
                raise AuthError("Use an access token for the configured public app client")
            if not isinstance(claims["sub"], str) or claims["sub"] not in self.settings.memberships:
                raise AuthError("User is not enrolled in this demo incident")
        except (jwt.PyJWTError, ValueError, KeyError, TypeError):
            raise AuthError("Invalid or expired access token") from None
        return Principal(claims["sub"], self.settings.memberships[claims["sub"]])

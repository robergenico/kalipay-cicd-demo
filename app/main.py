"""Service de démo « comptes » de Kalipay (zone Z1 / back-end appli).

Il ne manipule que des jetons de carte, jamais de PAN (exigence E2).
"""
import os
import re

from flask import Flask, abort, jsonify
from waitress import serve

app = Flask(__name__)

# Jeton de carte au format tok_<24 caractères> : le PAN reste dans le coffre (Z9).
TOKEN_RE = re.compile(r"^tok_[A-Za-z0-9]{24}$")

FAKE_ACCOUNTS = {
    "tok_4f9a1c2b7d3e8f0a1b2c3d4e": {"titulaire": "Boulangerie Martin", "solde_eur": 1520.40},
}


@app.after_request
def en_tetes_securite(resp):
    # En-têtes vérifiés par le DAST (ZAP) dans le pipeline
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
    resp.headers["Cache-Control"] = "no-store"
    return resp


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/api/comptes/<token>")
def compte(token: str):
    if not TOKEN_RE.match(token):
        abort(400)
    compte = FAKE_ACCOUNTS.get(token)
    if compte is None:
        abort(404)
    return jsonify(token=token, **compte)


if __name__ == "__main__":
    serve(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))

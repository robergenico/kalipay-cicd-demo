# Étape 1 : installation des dépendances dans une image complète
FROM python:3.13-slim-trixie AS build
WORKDIR /build
COPY app/requirements.txt .
RUN pip install --no-cache-dir --target /deps -r requirements.txt

# Étape 2 : image finale distroless, sans shell ni gestionnaire de paquets,
# avec l'utilisateur non-root 65532 (exigence du livrable 13)
FROM gcr.io/distroless/python3-debian13:nonroot
WORKDIR /app
COPY --from=build /deps /deps
COPY app/ /app/
ENV PYTHONPATH=/deps PORT=8080
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["python3", "/app/main.py"]

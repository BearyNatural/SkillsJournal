FROM python:3.8-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y stress && \
    pip install Flask

COPY app.py .

CMD [ "python", "app.py" ]

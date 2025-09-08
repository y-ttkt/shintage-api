FROM golang:1.21.5
ENV TZ=Asia/Tokyo

WORKDIR /app

RUN go install github.com/cosmtrek/air@v1.49.0
COPY go.mod go.sum .air.toml ./
RUN go mod download

CMD ["air", "-c", ".air.toml"]
FROM golang:1.25 AS builder
WORKDIR /app
COPY main.go .
RUN go mod init guestbook && go mod tidy
RUN CGO_ENABLED=0 go build -trimpath -o /app/guestbook main.go

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=builder /app/guestbook ./guestbook
COPY public/index.html public/script.js public/style.css public/jquery.min.js ./public/
EXPOSE 3000
USER 65532:65532
CMD ["./guestbook"]

FROM nginx:alpine

RUN echo 'server { \
    listen 80; \
    server_name localhost; \
    location / { \
        root /usr/share/nginx/html; \
        index index.html index.htm; \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

COPY build/web /usr/share/nginx/html

EXPOSE 80

LABEL org.opencontainers.image.source="https://github.com/dstweihao/dst-echomind-app"
LABEL org.opencontainers.image.description="回响 (EchoMind) Web 容器镜像"

CMD ["nginx", "-g", "daemon off;"]

FROM nginx:latest
RUN apt-get update \
    # debug stuff to test reaching /api through proxy_pass
    && apt-get install -y iputils-ping netcat curl procps \
    && mkdir -p /www/data
COPY testeget.html /www/data/index.html
COPY nginx/app/*.conf /etc/nginx/conf.d/
COPY nginx/nginx.conf /etc/nginx/nginx.conf
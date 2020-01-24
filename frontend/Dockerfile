FROM nginx:latest
RUN apt-get update && apt-get install -y iputils-ping netcat curl procps # debug stuff to test reaching api through proxy_pass
COPY testeget.html /var/www/html/index.html
COPY nginx/app/*.conf /etc/nginx/conf.d/
COPY nginx/nginx.conf /etc/nginx/nginx.conf
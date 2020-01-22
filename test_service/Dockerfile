FROM nginx:latest
RUN apt-get update && apt-get install -y iputils-ping netcat curl procps # debug staff for reach api
COPY testeget.html /var/www/html/index.html
COPY app.conf /etc/nginx/conf.d/app.conf
COPY upstream.conf /etc/nginx/conf.d/
COPY nginx.conf /etc/nginx/nginx.conf
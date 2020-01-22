FROM python:3.8-alpine
ARG http_proxy
WORKDIR /app
ENV FLASK_APP='server.py' HOST='0.0.0.0' PORT='8080'
ADD requirements.txt /app/requirements.txt
RUN if [ ! -z "${http_proxy}" ]; then \
        pip3 install --proxy "${http_proxy}" -r requirements.txt; \
    else \
        pip3 install -r requirements.txt; \
    fi
ADD . /app/
ENTRYPOINT ['python']
CMD ['/app/server.py']
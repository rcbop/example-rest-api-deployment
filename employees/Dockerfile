FROM python:3.8-alpine
WORKDIR /app
ADD employees/requirements.txt /app/requirements.txt
RUN pip3 install -r requirements.txt
ADD employees/*.py /app/
ADD data/chinook.db /app/data/chinook.db
VOLUME ["/app/data/"]
ENTRYPOINT ["python3"]
CMD ["server.py"]
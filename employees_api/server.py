import os
import json
from json import dumps

from flask import Flask, request
from flask_cors import CORS
from flask_jsonpify import jsonify
from flask_restful import Api, Resource
from sqlalchemy import create_engine

HOSTNAME = os.getenv('HOST', 'localhost')
PORT = os.getenv('PORT', '5000')
DB_FILE = os.getenv('DB_FILE', 'chinook.db')
API_PREFIX = os.getenv('API_PREFIX')

db_connect = create_engine(f'sqlite:///data/{DB_FILE}')
app = Flask(__name__)

if API_PREFIX:
    app.logger.info(f'using API_PREFIX :: {API_PREFIX}')
    api = Api(app, prefix=API_PREFIX)
else:
    api = Api(app)

CORS(app)

class Employees(Resource):
    def get(self):
        conn = db_connect.connect() # connect to database
        query = conn.execute("select * from employees") # This line performs query and returns json result
        return {'employees': [i[0] for i in query.cursor.fetchall()]} # Fetches first column that is Employee ID

class Tracks(Resource):
    def get(self):
        conn = db_connect.connect()
        query = conn.execute("select trackid, name, composer, unitprice from tracks;")
        result = {'data': [dict(zip(tuple (query.keys()) ,i)) for i in query.cursor]}
        return jsonify(result)

class Employees_Name(Resource):
    def get(self, employee_id):
        conn = db_connect.connect()
        query = conn.execute("select * from employees where EmployeeId =%d "  %int(employee_id))
        result = {'data': [dict(zip(tuple (query.keys()) ,i)) for i in query.cursor]}
        return jsonify(result)

class Employees_Name_Delete(Resource):
	def delete(self, employee_id):
		conn = db_connect.connect()
		query = conn.execute("delete from employees where EmployeeId = %d" %int(employee_id))

class Employees_Title_Update(Resource):
	def post(self, employee_id):
		conn = db_connect.connect()
		j = request.get_json(force=True)
		newTitle=j.get('title')
		conn.execute("update employees set title=" + "'" + str(newTitle) + "'" + " where EmployeeId=%d" %int(employee_id))


api.add_resource(Employees, '/employees') # Route_1
api.add_resource(Tracks, '/tracks') # Route_2
api.add_resource(Employees_Name, '/employees/<employee_id>') # Route_3
api.add_resource(Employees_Name_Delete,'/employees_delete/<employee_id>') #teste com remocao
api.add_resource(Employees_Title_Update,'/employees_update/<employee_id>') #atualiza titulo


if __name__ == '__main__':
    app.run(host=HOSTNAME, port=PORT)

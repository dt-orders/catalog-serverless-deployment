import sys
import logging
import pymysql
import json
import os
import azure.functions as func
from decimal import *
import pathlib
from dynatrace.opentelemetry.azure.functions import wrap_handler
from opentelemetry.instrumentation.pymysql import PyMySQLInstrumentor
#from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
#from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
#from opentelemetry._logs import set_logger_provider

@wrap_handler
def main(req: func.HttpRequest) -> func.HttpResponse:
    PyMySQLInstrumentor().instrument()
    # rds settings
    user_name = os.environ["USER_NAME"]
    password = os.environ["PASSWORD"]
    rds_host = os.environ["RDS_HOST"]
    db_name = os.environ["DB_NAME"]

    logger = logging.getLogger()
    logger.setLevel(logging.INFO)

    #get current path for ssl cert
    current_path = pathlib.Path(__file__).parent.parent
    print(current_path)
    ssl_cert_path = str(current_path /  'DigiCertGlobalRootCA.crt.pem')

    # create the database connection outside of the handler to allow connections to be
    # re-used by subsequent function invocations.
    try:
        conn = pymysql.connect(
            host=rds_host,
            user=user_name,
            passwd=password,
            db=db_name,
            connect_timeout=5,
            ssl_ca=ssl_cert_path,
        )

    except pymysql.MySQLError as e:
        logger.error("ERROR: Unexpected error: Could not connect to MySQL instance.")
        logger.error(e)
        sys.exit()

    logger.info("SUCCESS: Connection to RDS MySQL instance succeeded")
    """
    This gets records by name
    """
    # message = event['Records'][0]['body']
    """
    data = json.dumps(message)
    data = message
    logger.info(data)    
    body = json.loads(message["body"])
        # logger.info(body)
        # logger.info(type(body))

    name = body["name"]
    """
    name = req.params.get('name')
    if not name:
        try:
            req_body = req.get_json()
        except ValueError:
            pass
        else:
            name = req_body.get('name')

    logger.info(name)

    item_count = 0

    with conn.cursor() as cursor:
        sql = "SELECT `name`, `price` FROM `catalog` WHERE `name`=%s"
        cursor.execute(sql, ({name},))

        row_headers=[x[0] for x in cursor.description] #this will extract row headers
        rv = cursor.fetchall()

        json_data = []
        for row in rv:
            row_data = []
            for data in row:
                # print(type(data))
                if type(data) is Decimal:
                    # row_data.append(float(Decimal(data).quantize(Decimal('.01'))))
                    row_data.append("%.2f" % float(Decimal(data).quantize(Decimal('.01'))))
                else:
                    row_data.append(str(data))
            json_data.append(dict(zip(row_headers,row_data)))
        output_json = (json.dumps(json_data))  

    response = {
        "statusCode": 200,
        "headers": {},
        "body": output_json
    }

    
    return func.HttpResponse(
        output_json,
        status_code=200
    )
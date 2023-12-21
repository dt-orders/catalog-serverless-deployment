import shared_code.dt_helper
import logging
import os
import azure.functions as func
import pymysql
import pathlib
from dynatrace.opentelemetry.azure.functions import wrap_handler
from opentelemetry.instrumentation.pymysql import PyMySQLInstrumentor
#from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
#from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
#from opentelemetry._logs import set_logger_provider

@wrap_handler
def main(req: func.HttpRequest, context: func.Context) -> func.HttpResponse:
    
    PyMySQLInstrumentor().instrument()
    
    logging.info('Python HTTP trigger function processed a request.')
    #get current path for ssl cert
    current_path = pathlib.Path(__file__).parent.parent
    print(current_path)
    ssl_cert_path = str(current_path /  'DigiCertGlobalRootCA.crt.pem')

     # rds settings
    user_name = os.environ["USER_NAME"]
    password = os.environ["PASSWORD"]
    rds_host = os.environ["RDS_HOST"]
    db_name = os.environ["DB_NAME"]

    # Connect to MySQL
    cnx = pymysql.connect(
        host=rds_host,
        user=user_name,
        passwd=password,
        db=db_name,
        connect_timeout=5,
        ssl_ca=ssl_cert_path,
    )
    logging.info(cnx)
    # Show catalog table
    cursor = cnx.cursor()
    sql_string = "select * from catalog"
    cursor.execute(sql_string)
    result_list = cursor.fetchall()
    # Build result response text
    result_str_list = []
    for row in result_list:
        row_str = ', '.join([str(v) for v in row])
        result_str_list.append(row_str)
    result_str = '\n'.join(result_str_list)
    return func.HttpResponse(
        result_str,
        status_code=200
    )
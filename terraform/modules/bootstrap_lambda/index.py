import pg8000.native
import os

def handler(event, context):
    host = os.environ['DB_HOST'].split(':')[0]
    password = os.environ['DB_PASSWORD']
    db_list = ['reviewer_prod', 'check_prod']
    
    try:
        # pg8000 uses a different syntax
        conn = pg8000.native.Connection(user='postgres', host=host, password=password, database='postgres')
        
        results = []
        for db in db_list:
            try:
                # Need to be careful with CREATE DATABASE in transactions
                # pg8000.native doesn't easily support autocommit off for specific commands
                # We'll use a new connection for each to be safe
                conn.run(f"CREATE DATABASE {db}")
                results.append(f"Created {db}")
            except Exception as e:
                results.append(f"Skipped {db}: {str(e)}")
            
            # Connect to each to enable extensions
            db_conn = pg8000.native.Connection(user='postgres', host=host, password=password, database=db)
            db_conn.run("CREATE EXTENSION IF NOT EXISTS postgis")
            db_conn.run("CREATE EXTENSION IF NOT EXISTS vector")
            db_conn.close()
            results.append(f"Enabled extensions in {db}")
            
        conn.close()
        return {"status": "success", "results": results}
    except Exception as e:
        return {"status": "error", "message": str(e)}

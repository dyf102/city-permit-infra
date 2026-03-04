import psycopg2
import sys
import os

def bootstrap_db(host, user, password, db_list):
    try:
        # Connect to default postgres DB
        conn = psycopg2.connect(
            host=host,
            database="postgres",
            user=user,
            password=password
        )
        conn.autocommit = True
        cur = conn.cursor()

        for db in db_list:
            print(f"Creating database: {db}...")
            try:
                cur.execute(f"CREATE DATABASE {db}")
            except Exception as e:
                if "already exists" in str(e):
                    print(f"Database {db} already exists.")
                else:
                    raise e

            # Connect to new DB to create extensions
            db_conn = psycopg2.connect(
                host=host,
                database=db,
                user=user,
                password=password
            )
            db_conn.autocommit = True
            db_cur = db_conn.cursor()

            print(f"Enabling PostGIS and Vector in {db}...")
            db_cur.execute("CREATE EXTENSION IF NOT EXISTS postgis")
            db_cur.execute("CREATE EXTENSION IF NOT EXISTS vector")
            
            db_cur.close()
            db_conn.close()

        cur.close()
        conn.close()
        print("Bootstrap complete!")

    except Exception as e:
        print(f"Error during bootstrap: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python bootstrap_db.py <host> <user> <password>")
        sys.exit(1)
    
    bootstrap_db(sys.argv[1], sys.argv[2], sys.argv[3], ["reviewer_prod", "check_prod"])

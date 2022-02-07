import json
import uuid
import boto3
import random
import datetime
import argparse
import logging
from faker import Faker

# Define log format
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s', datefmt='%Y-%d-%mT%H:%M:%S')

# Define Kinesis client service using the us-east-1 region
kinesis = boto3.client('kinesis', region_name='us-east-1')

# Function to produce data
def data_producer():
    fake_data = Faker()
    time_now = datetime.datetime.now()
    time_now_string = time_now.isoformat()
    record_data = {
            'uuid': str(uuid.uuid4()),
            'event_date': time_now_string,
            'status': fake_data.random_element(elements=("Active", "Inactive", "Canceled")),
            'name': fake_data.first_name(),
            'last_name': fake_data.last_name(),
            'email': fake_data.email(),
            'phone': random.randint(900000000, 999999999)
    }
    return record_data


def data_sender(max_record):
        record_count = 0
        # Create the data and send it to our Kinesis Data Stream
        while record_count < max_record:
                data = json.dumps(data_producer())
                print(data)
                try:
                        kinesis.put_record(
                                StreamName="kinesis-rd-stream",
                                Data=data,
                                PartitionKey="partitionkey")
                except Exception as e:
                        logging.error(f"Fail to deliver message - {str(e)}")
                record_count += 1


if __name__ == '__main__':
    app_parser = argparse.ArgumentParser(allow_abbrev=False)
    app_parser.add_argument('--amount',
                            action='store',
                            type=int,
                            required=True,
                            dest='amount_opt',
                            help='Set the amount of message records to be generated.')
    args = app_parser.parse_args()
    logging.info(f"Started data generation.")
    data_sender(args.amount_opt)
    logging.info(f"{args.amount_opt} messages delivered to Kinesis.")
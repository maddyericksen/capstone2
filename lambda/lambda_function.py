import boto3
import json

def lambda_handler(event, context):
    # TODO implement
    s3 = boto3.client("s3")
    bucket = "grp3-cap2b-data"
    key = "todo-data.json"
    response = s3.get_object(Bucket=bucket, Key=key)
    json_data = response["Body"].read().decode("utf-8")
    json_content = json.loads(json_data)
    return {
        'statusCode': 200,
        'body': json_content
}
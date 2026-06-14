import boto3
import json
import os
from datetime import datetime

# Read settings from environment variables (set by Terraform)
REPORTS_BUCKET = os.environ['REPORTS_BUCKET']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')

    response = ec2.describe_volumes(
        Filters=[{'Name': 'status', 'Values': ['available']}]
    )

    unattached = []
    for volume in response['Volumes']:
        unattached.append({
            'VolumeId': volume['VolumeId'],
            'SizeGB': volume['Size'],
            'Created': str(volume['CreateTime'])
        })

    print(f"Found {len(unattached)} unattached EBS volumes")
    for vol in unattached:
        print(vol)

        # --- Check 2: stopped EC2 instances ---
    stopped_instances = []
    instances = ec2.describe_instances(
        Filters=[{'Name': 'instance-state-name', 'Values': ['stopped']}]
    )

    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            stopped_instances.append({
                'InstanceId': instance['InstanceId'],
                'Type': instance['InstanceType'],
                'StoppedSince': str(instance.get('StateTransitionReason', 'unknown'))
            })

    print(f"Found {len(stopped_instances)} stopped EC2 instances")

    # --- Check 3: untagged EC2 instances ---
    untagged = []
    all_instances = ec2.describe_instances()

    for reservation in all_instances['Reservations']:
        for instance in reservation['Instances']:
            if not instance.get('Tags'):
                untagged.append({
                    'InstanceId': instance['InstanceId'],
                    'Type': instance['InstanceType'],
                    'State': instance['State']['Name']
                })

    print(f"Found {len(untagged)} untagged EC2 instances")
    # --- Save report to S3 ---
    s3 = boto3.client('s3')

    report = {
        'scan_date': str(datetime.now()),
        'unattached_volumes': unattached,
        'stopped_instances': stopped_instances,
        'untagged_instances': untagged
    }

    filename = f"reports/{datetime.now().strftime('%Y-%m-%d')}.json"

   s3.put_object(
        Bucket=REPORTS_BUCKET,
        Key=filename,
        Body=json.dumps(report, indent=2)
    )

    print(f"Report saved to S3: {filename}")
    # --- Send summary email via SNS ---
    sns = boto3.client('sns')

    summary = (
        f"Cost Optimiser daily scan complete.\n\n"
        f"Unattached EBS volumes: {len(unattached)}\n"
        f"Stopped EC2 instances: {len(stopped_instances)}\n"
        f"Untagged instances: {len(untagged)}\n\n"
        f"Full report: s3://{REPORTS_BUCKET}/{filename}"
    )

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject='AWS Cost Optimiser - Daily Report',
        Message=summary
    )

    print("Summary email sent")
    return {
        'statusCode': 200,
        'unattached_volumes': unattached,
        'unattached_count': len(unattached),
        'stopped_instances': stopped_instances,
        'stopped_count': len(stopped_instances),
        'untagged_instances': untagged,
        'untagged_count': len(untagged)
    }

import boto3
# boto3.set_stream_logger('') # this is used for testing the code

# variables
region = 'ap-southeast-2'
repo = 'my-repository'

client = boto3.client('ecr', region_name = region)
response = client.describe_images(
    repositoryName = repo
)

for image in response['imageDetails']:
    print(image['imageTags'])
    
# import boto3 
# client = boto3.client('ecr')
# response = client.list_tags_for_resource(
#     resourceArn='arn:aws:ecr:ap-southeast-2:ACCOUNT_ID:repository/my-repository' # arn:aws:ecr:region:account-id:repository/repository-name
# )
# print(response)
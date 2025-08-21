testing creation and attachment of ebs for cx replication

aws ec2 create-volume --availability-zone ap-southeast-2a --size 10 --volume-type gp3
# note volume id: vol-0863bab5cb2c07297

# create storage-class.yaml see yaml
kubectl apply -f storage-class.yaml

# Create pv.yaml update the volume id into the handler section and change format as required, it also contains the pvc.yaml
kubectl apply -f pv.yaml

# create the pod.yaml
kubectl apply -f pod.yaml


# to clean up
kubectl delete -f pod.yaml
kubectl delete -f pv.yaml
kubectl delete -f storage-class.yaml

# troubleshooting:
aws ec2 describe-volumes --volume-ids vol-0a30a5f00f9eb433a --query "Volumes[].Attachments"
aws ec2 describe-volume-status --volume-id vol-0a30a5f00f9eb433a
aws ec2 delete-volume-attachment --volume-attachment-id <attachment-id>
aws ec2 describe-instances --instance-ids i-03e54f399f14026dc --query "Reservations[].Instances[].MetadataOptions"
# need to see 2 hops if one 1 then 
aws ec2 modify-instance-metadata-options \
    --instance-id i-03e54f399f14026dc \
    --http-endpoint enabled \
    --http-tokens optional
# standard link-local address used by the EC2 Instance Metadata Service (IMDS) in AWS
curl http://169.254.169.254/latest/meta-data/
 	
Content-Type: multipart/mixed; boundary="==BOUNDARY==" 
MIME-Version: 1.0 

--==BOUNDARY== 
MIME-Version: 1.0 
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash 
echo ECS_CLUSTER=${CLUSTER}>>/etc/ecs/ecs.config 
echo ECS_DISABLE_IMAGE_CLEANUP=false>>/etc/ecs/ecs.config 
echo ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=2m>>/etc/ecs/ecs.config 
echo ECS_IMAGE_CLEANUP_INTERVAL=10m>>/etc/ecs/ecs.config 
echo ECS_IMAGE_MINIMUM_CLEANUP_AGE=10m>>/etc/ecs/ecs.config 
echo ECS_NUM_IMAGES_DELETE_PER_CYCLE=5>>/etc/ecs/ecs.config
echo ECS_RESERVED_MEMORY=32>>/etc/ecs/ecs.config
echo ECS_INSTANCE_ATTRIBUTES={\"com.amazonaws.batch.compute-environment-revision\":\"2\"}>>/etc/ecs/ecs.config
--==BOUNDARY==
MIME-Version: 1.0
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
echo ECS_CLUSTER=${CLUSTER}>>/etc/ecs/ecs.config

--==BOUNDARY==--
{
    "family": "fargate-task-definition",
    "networkMode": "awsvpc",
    "containerDefinitions": [
      {
        "name": "nginx",
        "image": "nginx:latest",
        "cpu": 256,
        "memory": 512,
        "portMappings": [
          {
            "containerPort": 80,
            "hostPort": 80,
            "protocol": "tcp"
          }
        ],
        "essential": true,
        "entryPoint": [
          "sh",
          "-c"
        ],
        "command": [
          "/bin/sh -c \"echo 'Hello, World!' > /usr/share/nginx/html/index.html && nginx -g 'daemon off;'\""
        ]
      }
    ],
    "requiresCompatibilities": [
      "FARGATE"
    ],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "arn:aws:iam::ACCOUNT_ID:role/ecsTaskExecutionRole",
}  
# Start stress on 2 CPU cores
curl -X POST http://[CONTAINER_IP]:8080/start_stress?cpu=2

# Stop the stress
curl -X POST http://[CONTAINER_IP]:8080/stop_stress

from flask import Flask, request
import subprocess
import os

app = Flask(__name__)
stress_process = None

@app.route('/start_stress', methods=['POST'])
def start_stress():
    global stress_process
    cpu = request.args.get('cpu', default=1, type=int)
    if stress_process:
        stress_process.terminate()
    stress_process = subprocess.Popen(["stress", "--cpu", str(cpu)])
    return "Stress started with {} CPUs".format(cpu)

@app.route('/stop_stress', methods=['POST'])
def stop_stress():
    global stress_process
    if stress_process:
        stress_process.terminate()
        stress_process = None
    return "Stress stopped"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)

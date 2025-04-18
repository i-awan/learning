from flask import Flask, request, send_from_directory
import subprocess

app = Flask(__name__)

AUTH_PASSWORD = "supersecret"  # hardcoded for simplicity

@app.route('/')
def form():
    return send_from_directory('.', 'index.html')

@app.route('/trigger', methods=['POST'])
def trigger():
    username = request.form.get('username')
    password = request.form.get('password')

    if password != AUTH_PASSWORD:
        return "Unauthorized", 403

    curl_command = [
        'curl', '-X', 'POST', 'https://external-api.com/endpoint',
        '-H', 'Content-Type: application/json',
        '--data-raw', f'''{{
            "input_token_state": {{
                "token_type": "CREDENTIAL",
                "username": "{username}",
                "password": "{password}"
            }}
        }}'''
    ]

    try:
        result = subprocess.check_output(curl_command, stderr=subprocess.STDOUT)
        return f"<pre>{result.decode()}</pre>"
    except subprocess.CalledProcessError as e:
        return f"<pre>Failed:\n{e.output.decode()}</pre>", 500

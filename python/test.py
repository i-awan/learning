import requests
from bs4 import BeautifulSoup

# URLs
login_url = "https://example.com/login"
protected_url = "https://example.com/dashboard"

# Start a session so cookies (including CSRF cookies) are kept
session = requests.Session()

# 1) Get the login page (this gives us the CSRF token in the HTML)
r = session.get(login_url)
r.raise_for_status()

# 2) Parse the CSRF token out of the HTML
soup = BeautifulSoup(r.text, "html.parser")

# Adjust the selector to match your site's HTML
csrf_input = soup.find("input", {"name": "csrf_token"})
csrf_token = csrf_input["value"]

print("CSRF token:", csrf_token)

# 3) Build the login payload (include username, password, and the CSRF token)
payload = {
    "username": "your_username",
    "password": "your_password",
    "csrf_token": csrf_token,
}

# Optional: often you should send the same headers a browser would send
headers = {
    "User-Agent": "Mozilla/5.0",
}

# 4) POST to log in
login_resp = session.post(login_url, data=payload, headers=headers)
login_resp.raise_for_status()

# Quick sanity check: does the response look like a logged-in page?
print("After login URL:", login_resp.url)

# 5) Use the same session to access the protected page
protected_resp = session.get(protected_url, headers=headers)
protected_resp.raise_for_status()

# Print the HTML of the protected page
print(protected_resp.text)

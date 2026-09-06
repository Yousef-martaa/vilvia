import json

import jinja2
from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from app.core.settings import settings

router = APIRouter(tags=["web"])

_HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Delete Account | Vilvia</title>
    <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 500px;
            margin: 40px auto;
            padding: 0 20px;
            background-color: #f9f9f9;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #d32f2f; margin-top: 0; }
        .disclosure {
            background: #fff8f8;
            border-left: 4px solid #d32f2f;
            padding: 15px;
            margin: 20px 0;
            font-size: 0.9em;
        }
        form { display: flex; flex-direction: column; gap: 15px; }
        input {
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 16px;
        }
        button {
            padding: 12px;
            background-color: #d32f2f;
            color: white;
            border: none;
            border-radius: 4px;
            font-size: 16px;
            cursor: pointer;
            font-weight: bold;
        }
        button:disabled { background-color: #ccc; cursor: not-allowed; }
        .error { color: #d32f2f; font-size: 0.9em; margin-top: 10px; display: none; }
        .success { color: #2e7d32; display: none; }
        .loading { display: none; margin-top: 10px; color: #666; }
        footer { margin-top: 40px; text-align: center; font-size: 0.8em; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Vilvia</h1>
        <h2>Account Deletion Request</h2>

        <p>You are requesting the permanent deletion of your Vilvia account.</p>

        <div class="disclosure">
            <strong>Important: This is destructive.</strong>
            <p>Fulfillment will permanently remove:</p>
            <ul>
                <li>Your account identity and Profile</li>
                <li>Every Post and Comment you authored</li>
                <li>All your reactions and reports</li>
                <li>Threads below your Posts (via existing cascades)</li>
            </ul>
            <p>Admin-created Events are retained. Requests are processed asynchronously and deletion may not be immediate.</p>
        </div>

        <div id="auth-section">
            <p>Please sign in to verify ownership of your account:</p>
            <form id="deletion-form">
                <input type="email" id="email" placeholder="Email" required autocomplete="email">
                <input type="password" id="password" placeholder="Password" required autocomplete="current-password">
                <button type="submit" id="submit-btn">Verify and Request Deletion</button>
            </form>
            <div id="error-msg" class="error"></div>
            <div id="loading-msg" class="loading">Processing request...</div>
        </div>

        <div id="success-section" class="success">
            <h3>Request Accepted</h3>
            <p>Your account deletion request has been recorded. You have been signed out.</p>
            <p>Fulfillment will proceed according to our deletion policy.</p>
        </div>
    </div>

    <footer>
        &copy; 2026 Vilvia | Developed for Google Play
    </footer>

    <script>
        const config = {{ config_json | safe }};
        let supabaseClient;

        const form = document.getElementById('deletion-form');
        const submitBtn = document.getElementById('submit-btn');
        const errorMsg = document.getElementById('error-msg');
        const loadingMsg = document.getElementById('loading-msg');
        const authSection = document.getElementById('auth-section');
        const successSection = document.getElementById('success-section');

        // Check if Supabase SDK loaded
        if (typeof supabase === 'undefined') {
            errorMsg.textContent = 'The authentication service could not be loaded. Please check your internet connection or try again later.';
            errorMsg.style.display = 'block';
            submitBtn.disabled = true;
        } else {
            const { createClient } = supabase;
            supabaseClient = createClient(config.supabase_url, config.supabase_key);
        }

        form.addEventListener('submit', async (e) => {
            e.preventDefault();

            const email = document.getElementById('email').value;
            const password = document.getElementById('password').value;

            errorMsg.style.display = 'none';
            loadingMsg.style.display = 'block';
            submitBtn.disabled = true;

            try {
                const { data, error: authError } = await supabaseClient.auth.signInWithPassword({
                    email,
                    password,
                });

                if (authError) throw new Error(authError.message);

                const session = data.session;
                if (!session) throw new Error('Could not establish session.');

                const response = await fetch('/me/account-deletion-request', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${session.access_token}`,
                    }
                });

                if (!response.ok) {
                    const detail = await response.json().then(j => j.detail).catch(() => 'Request failed');
                    throw new Error(detail);
                }

                await supabaseClient.auth.signOut();

                authSection.style.display = 'none';
                successSection.style.display = 'block';

            } catch (err) {
                errorMsg.textContent = err.message;
                errorMsg.style.display = 'block';
                submitBtn.disabled = false;
            } finally {
                loadingMsg.style.display = 'none';
            }
        });
    </script>
</body>
</html>
"""

_template = jinja2.Template(_HTML_TEMPLATE)

@router.get("/deletion-request", response_class=HTMLResponse)
async def get_deletion_request_page():
    """Serve a lightweight, standalone account deletion request form."""
    config = {
        "supabase_url": settings.supabase_url,
        "supabase_key": settings.supabase_publishable_key,
    }
    return _template.render(config_json=json.dumps(config))

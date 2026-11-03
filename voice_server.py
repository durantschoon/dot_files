import http.server
import json
import glob
import os
import re
import subprocess

PORT = 8642
LOGS_DIR = 'logs'

def get_live_tmux_sessions():
    cmd = ['zsh', '-c', 'source .jobs.zsh && _tmux_pick_lines --all 2>/dev/null; print -l -- "${reply[@]}"']
    result = subprocess.run(cmd, capture_output=True, text=True)
    sessions = []
    
    seen = set()
    for line in result.stdout.strip().split('\n'):
        if not line.strip():
            continue
        if line in seen:
            continue
        seen.add(line)
        
        parts = line.split('\t')
        if len(parts) >= 2:
            id_part = parts[0]
            display_part = parts[1].strip()
            path_part = parts[2].strip() if len(parts) >= 3 else ""
            
            host, _, job_id = id_part.partition('|')
            
            # Look for extranotes and outbox in the job's directory
            extranotes = None
            outbox = ""
            if path_part and os.path.isdir(path_part):
                extranotes_path = os.path.join(path_part, "extranotes")
                if os.path.exists(extranotes_path):
                    with open(extranotes_path, "r") as f:
                        extranotes = f.read().strip()
                
                # Check for an outbox (e.g. logs/job_id.outbox or just .outbox)
                outbox_path = os.path.join(path_part, "logs", f"{job_id}.outbox")
                if os.path.exists(outbox_path):
                    with open(outbox_path, "r") as f:
                        outbox = f.read().strip()

            sessions.append({
                'id': job_id,
                'host': host,
                'status_line': display_part,
                'path': path_part,
                'extranotes': extranotes,
                'outbox': outbox
            })
    return sessions

class VoiceIntegrationHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            live_sessions = get_live_tmux_sessions()
            status_payload = {
                'live_sessions': live_sessions,
                'jobs': {}
            }
            
            # Map the live sessions into the jobs dictionary for the Gemini agent
            for sess in live_sessions:
                job_id = sess['id']
                status_payload['jobs'][job_id] = {
                    'outbox': sess['outbox'],
                    'blocked_question': sess['extranotes'],
                    'path': sess['path']
                }

            self.wfile.write(json.dumps(status_payload).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        # Expecting path like /inbox/job-id
        match = re.match(r'^/inbox/([^/]+)$', self.path)
        if match:
            job_name = match.group(1)
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            try:
                data = json.loads(post_data.decode('utf-8'))
                answer = data.get('answer', '')
                
                # Try to find the job's path from live sessions to write to its real inbox
                live_sessions = get_live_tmux_sessions()
                job_path = None
                for sess in live_sessions:
                    if sess['id'] == job_name:
                        job_path = sess['path']
                        break
                
                if job_path and os.path.isdir(job_path):
                    inbox_path = os.path.join(job_path, "inbox")
                    with open(inbox_path, 'a') as f:
                        f.write(f"{answer}\n")
                else:
                    # Fallback to local logs directory if not a real tmux job
                    os.makedirs(LOGS_DIR, exist_ok=True)
                    inbox_path = os.path.join(LOGS_DIR, f"{job_name}.inbox")
                    with open(inbox_path, 'a') as f:
                        f.write(f"{answer}\n")
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'status': 'success', 'job': job_name}).encode('utf-8'))
            except json.JSONDecodeError:
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server_address = ('', PORT)
    httpd = http.server.HTTPServer(server_address, VoiceIntegrationHandler)
    print(f"Starting voice integration server on port {PORT}...")
    print(f"Waiting for jobs in ./{LOGS_DIR}/")
    httpd.serve_forever()

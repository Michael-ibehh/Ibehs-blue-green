# Blue-Green Deployment with Nginx & Docker

A **zero-downtime**, **self-healing** Blue-Green deployment system using **Nginx** as a smart reverse proxy and **Docker Compose** to orchestrate two application environments (`blue` and `green`). Traffic is automatically routed to the healthy instance with **no client failures**.

---

## Key Features

- **Zero failed client requests** during failover
- **Automatic failover** from Blue to Green on error
- **Automatic recovery** back to Blue after fix
- **Header forwarding**: `X-App-Pool`, `X-Release-Id`
- **Chaos injection** via `/chaos` endpoint
- **Automated verification** with `verify.sh`
- **Fully containerized** using Docker Compose
- **Deployed on AWS EC2**

---

## Architecture
Client
   ↓ (port 8080)
[Nginx Reverse Proxy]
   ├──► app_blue:3000  (Active by default)
   └──► app_green:3000 (Standby / Failover)


- **Nginx** uses `max_fails=2` and `fail_timeout=5s` to detect failures.
- On 2 failed checks, traffic **switches to Green**.
- After recovery, traffic **returns to Blue**.

---

## Project Structure
sf_blue-green/
├── docker-compose.yml

├── .env

├── verify.sh

├── nginx/

│   ├── nginx.conf.template

│   └── entrypoint.sh

└── README.md


---

## Prerequisites

**Tools:**
  Docker 
  Docker Compose 
  AWS EC2- Ubuntu

---

## Setup & Deployment on AWS EC2

### 1. Launch EC2 Instance
- **AMI**: Ubuntu (prefered- by author) 
- **Security Group**:
  - Allow **SSH (22)** from your IP
  - Allow **TCP 8080, 8081, 8082** from `0.0.0.0/0`

### 2. Install Docker
- curl -fsSL https://get.docker.com | sh
- sudo usermod -aG docker $USER
- newgrp docker

### 4. Transfer Project FilesFrom local machine:
- scp -i <your-key.pem(if any)> -r sf_blue-green ubuntu@<ec2-public-ip>:~/

### 5. Start Services
-  cd ~/sf_blue-green
-  docker compose up -d

## ⚠ Configuration
- Follow my .env.example, and configure .env 

### Run Automated Test
-  chmod +x verify.sh
-  ./verify.sh

**OR**

### Manual Testing
- 1. Check Blue (active)
curl -v http://<ec2-ip>:8080/version

- 2. Trigger failure on Blue
curl -X POST http://<ec2-ip>:8081/chaos/start?mode=error

- 3. Observe failover to Green
for i in {1..20}; do curl http://<ec2-ip>:8080/version; done

- 4. Stop chaos
curl -X POST http://<ec2-ip>:8081/chaos/stop

- 5. Verify recovery to Blue
sleep 5
curl -v http://<ec2-ip>:8080/version

**EndpointsURL & Purpose**

http://<ip>:8080/version-     Public API (via Nginx)

http://<ip>:8081/version-     Blue service

http://<ip>:8082/version-     Green service

POST /chaos/start?mode=error- Fail Blue

POST /chaos/stop-             Recover Blue

**Health ChecksNginx:**
- curl http://localhost/healthz → OK
- App: curl http://localhost:3000/healthz → 200

###Troubleshooting

**Issue & Fix**

Connection refused-   Check security group, docker compose ps

Unhealthy status-     Verify /healthz on port 3000

verify.sh hangs-      Run bash -x ./verify.sh

Permission denied-    chmod 400 key.pem, add to docker group

**Cleanup**
- docker compose down
- #Terminate EC2 instance in AWS Console

### Author
**Michael Ibeh**

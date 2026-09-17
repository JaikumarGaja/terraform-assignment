#!/bin/bash
apt-get update -y
apt-get install -y python3-pip python3-venv nodejs npm git
npm install -g pm2

# Clone your code
git clone https://github.com/JaikumarGaja/aws-assignment /home/ubuntu/app

# Auto-fetch Public IP and set frontend environment variable
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "BACKEND_URL=http://$PUBLIC_IP:5000" > /home/ubuntu/app/frontend/.env

# Setup and run Flask (Backend)
cd /home/ubuntu/app/backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pm2 start app.py --name "flask-backend" --interpreter ./venv/bin/python

# Setup and run Express (Frontend)
cd /home/ubuntu/app/frontend
npm install
pm2 start app.js --name "express-frontend"

pm2 save
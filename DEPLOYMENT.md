# Deployment Guide

This guide covers deploying the Press Connect application to production environments.

## Production Architecture

```
[Mobile App] -> [Load Balancer] -> [Backend API] -> [PostgreSQL Database]
                                      |
                                [YouTube API v3]
```

## Backend Deployment

### Docker Deployment (Recommended)

1. **Create Dockerfile**
```dockerfile
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

EXPOSE 5000

CMD ["npm", "start"]
```

2. **Create docker-compose.yml**
```yaml
version: '3.8'
services:
  app:
    build: .
    ports:
      - "5000:5000"
    environment:
      - DB_HOST=db
      - DB_NAME=press_connect_db
      - DB_USER=press_connect_user
      - DB_PASSWORD=${DB_PASSWORD}
      - JWT_SECRET=${JWT_SECRET}
      - ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
    depends_on:
      - db
    restart: unless-stopped

  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=press_connect_db
      - POSTGRES_USER=press_connect_user
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  postgres_data:
```

3. **Deploy with Docker Compose**
```bash
# Set environment variables
export DB_PASSWORD=your_secure_db_password
export JWT_SECRET=your_jwt_secret_32_characters_long
export ENCRYPTION_KEY=your_32_character_encryption_key
export GOOGLE_CLIENT_ID=your_google_client_id

# Deploy
docker-compose up -d
```

### Cloud Platform Deployment

#### Heroku

1. **Prepare for Heroku**
```bash
# Install Heroku CLI
heroku create press-connect-backend

# Add PostgreSQL addon
heroku addons:create heroku-postgresql:hobby-dev

# Set environment variables
heroku config:set JWT_SECRET=your_jwt_secret
heroku config:set ENCRYPTION_KEY=your_encryption_key
heroku config:set GOOGLE_CLIENT_ID=your_google_client_id
```

2. **Deploy**
```bash
git push heroku main
```

#### AWS ECS

1. **Create ECS Task Definition**
```json
{
  "family": "press-connect",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "press-connect-backend",
      "image": "your-repo/press-connect:latest",
      "portMappings": [
        {
          "containerPort": 5000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "DB_HOST",
          "value": "your-rds-endpoint"
        }
      ],
      "secrets": [
        {
          "name": "DB_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:region:account:secret:db-password"
        }
      ]
    }
  ]
}
```

#### Google Cloud Run

1. **Build and deploy**
```bash
# Build container
gcloud builds submit --tag gcr.io/PROJECT_ID/press-connect

# Deploy
gcloud run deploy press-connect \
  --image gcr.io/PROJECT_ID/press-connect \
  --platform managed \
  --region us-central1 \
  --set-env-vars DB_HOST=your-cloud-sql-ip \
  --set-env-vars GOOGLE_CLIENT_ID=your_client_id
```

### Database Setup

#### PostgreSQL on Cloud

**AWS RDS**
```bash
# Create RDS instance
aws rds create-db-instance \
  --db-instance-identifier press-connect-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username press_connect_user \
  --master-user-password YOUR_PASSWORD \
  --allocated-storage 20
```

**Google Cloud SQL**
```bash
# Create Cloud SQL instance
gcloud sql instances create press-connect-db \
  --database-version=POSTGRES_14 \
  --tier=db-f1-micro \
  --region=us-central1
```

#### Database Migration

The application automatically creates tables on startup. For production:

1. **Run initial setup**
```bash
# Connect to your database
psql -h your-db-host -U press_connect_user -d press_connect_db

# The app will create tables automatically on first run
# Or run migrations manually if needed
```

2. **Create initial admin user**
```bash
# The admin user will be created from local.config.json on first startup
# Or create manually:
curl -X POST http://your-backend-url/admin/users \
  -H "Authorization: Bearer YOUR_ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "secure_password",
    "associatedWith": null
  }'
```

## Frontend Deployment

### Mobile App Stores

#### Android (Google Play Store)

1. **Build release APK**
```bash
cd press_connect
flutter build apk --release
```

2. **Build App Bundle (recommended)**
```bash
flutter build appbundle --release
```

3. **Upload to Google Play Console**

#### iOS (Apple App Store)

1. **Build for iOS**
```bash
flutter build ios --release
```

2. **Archive and upload via Xcode**

### Web Deployment

1. **Build for web**
```bash
flutter build web --release
```

2. **Deploy to hosting platform**

**Firebase Hosting**
```bash
firebase init hosting
firebase deploy
```

**Netlify**
```bash
# Upload build/web directory to Netlify
```

**AWS S3 + CloudFront**
```bash
aws s3 sync build/web/ s3://your-bucket-name
aws cloudfront create-invalidation --distribution-id YOUR_DISTRIBUTION_ID --paths "/*"
```

## Security Considerations

### SSL/TLS Configuration

1. **Use HTTPS in production**
```bash
# Let's Encrypt with Certbot
sudo certbot --nginx -d your-domain.com
```

2. **Configure CORS properly**
```javascript
// In server.js
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['https://your-app.com'],
  credentials: true
}));
```

### Environment Variables

Never commit sensitive data. Use:

1. **Docker secrets**
2. **Cloud provider secret managers**
3. **Environment variable injection**

### Database Security

1. **Use SSL connections**
```javascript
// In database.js
ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
```

2. **Restrict database access**
3. **Regular backups**

## Monitoring and Logging

### Application Monitoring

1. **Add health checks**
```javascript
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    version: process.env.npm_package_version
  });
});
```

2. **Structured logging**
```javascript
const winston = require('winston');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'app.log' })
  ]
});
```

### Database Monitoring

1. **Connection pool monitoring**
2. **Query performance tracking**
3. **Database backups**

## Scaling

### Horizontal Scaling

1. **Load balancer configuration**
2. **Database connection pooling**
3. **Session store (Redis for multiple instances)**

### Performance Optimization

1. **Database indexing**
2. **Caching strategies**
3. **CDN for static assets**

## Backup and Recovery

### Database Backups

```bash
# Automated backup script
#!/bin/bash
BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)
pg_dump -h $DB_HOST -U $DB_USER $DB_NAME > "$BACKUP_DIR/backup_$DATE.sql"

# Keep only last 7 days
find $BACKUP_DIR -name "backup_*.sql" -mtime +7 -delete
```

### Application Backups

1. **Code repository backups**
2. **Configuration backups**
3. **User data backups**

## Troubleshooting

### Common Issues

1. **Database connection errors**
   - Check connection strings
   - Verify firewall rules
   - Check SSL requirements

2. **OAuth authentication failures**
   - Verify redirect URIs
   - Check client ID configuration
   - Validate SSL certificates

3. **Memory/performance issues**
   - Monitor resource usage
   - Check database query performance
   - Review connection pool settings

### Log Analysis

```bash
# Check application logs
docker logs press-connect-app

# Database logs
docker logs press-connect-db

# System resource usage
docker stats
```

## Maintenance

### Regular Tasks

1. **Update dependencies**
```bash
npm audit && npm update
```

2. **Database maintenance**
```sql
VACUUM ANALYZE;
REINDEX DATABASE press_connect_db;
```

3. **Log rotation**
4. **Security updates**
5. **Backup verification**

### Monitoring Checklist

- [ ] Application health endpoints
- [ ] Database connection status
- [ ] SSL certificate expiration
- [ ] Disk space usage
- [ ] Memory and CPU usage
- [ ] API response times
- [ ] Error rates

This deployment guide ensures a secure, scalable, and maintainable production deployment of the Press Connect application.
#!/bin/bash

# Check the value of ENABLE_NGINX
if [ "$ENABLE_FAKESERVER" = "true" ]; then
  echo "Starting Nginx..."
  supervisorctl start nginx
else
  echo "Skipping Nginx..."
fi

# Start the rest of Supervisor-managed services
supervisord -n

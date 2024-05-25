# Use the official Nginx image as the base image
FROM nginx:alpine

# Copy the custom HTML file to the default Nginx HTML location
COPY index.html /usr/share/nginx/html/index.html

# Base image with PHP & Nginx


docker buildx is require to build multiple archs

```docker buildx build --platform linux/amd64,linux/arm/v7 --push -t th0rn0/php-nginx-base:latest .```

Notes:

Some weird stuff going on with the builds. Need to investigate.

```systemctl status systemd-binfmt```

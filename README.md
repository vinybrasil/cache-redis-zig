# Caching API responses with Redis in Zig

In this project we use Redis to cache API responses with the Zap webframework, which is written in Zig. 
The full explanation of the code is in this [blogpost](https://vinybrasil.github.io/blog/cache-zig-redis/).

## To run it

Just clone the repository and run docker-compose:
```
docker-compose up
```

## Known issues

The IP of the Redis server depends on the internal IP of Docker. To find it, run
```
docker network inspect cache-redis-zig_default
```
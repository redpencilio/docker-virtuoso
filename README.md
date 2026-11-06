# Virtuoso docker

Docker image hosting the [OpenLink Virtuoso](http://virtuoso.openlinksw.com/) triplestore, built from source. It exposes a SPARQL/HTTP endpoint on port 8890 and an ODBC/SQL (ISQL) endpoint on port 1111.

The image is built from commit [ad6589ff38488183a35dfe8ba398233c3380b5ba](https://github.com/openlink/virtuoso-opensource/commit/ad6589ff38488183a35dfe8ba398233c3380b5ba) of https://github.com/openlink/virtuoso-opensource, which corresponds to Virtuoso 7.2.17.

## How-to guides

### How to run Virtuoso as a standalone container

Run the container with `docker run`, mounting a host folder as the Virtuoso database folder:

```sh
docker run --name my-virtuoso \
    -p 8890:8890 -p 1111:1111 \
    -e DBA_PASSWORD=myDbaPassword \
    -e SPARQL_UPDATE=true \
    -e DEFAULT_GRAPH=http://www.example.com/my-graph \
    -v ./data/db:/data \
    -d redpencil/virtuoso
```

`SPARQL_UPDATE=true` allows updates through the SPARQL endpoint. Check that Virtuoso finished its initial setup (setting the DBA password, loading files from `/data/toLoad`) with:

```sh
docker logs my-virtuoso
```

Query the store at `http://localhost:8890/sparql`.

### How to add Virtuoso to your docker compose stack

Add the following to your `docker-compose.yml`. The service is named `triplestore`, which is the default hostname used by the bundled scripts:

```yaml
services:
  triplestore:
    image: redpencil/virtuoso:1.4.0
    environment:
      SPARQL_UPDATE: "true"
      DEFAULT_GRAPH: "http://www.example.com/my-graph"
    volumes:
      - ./data/db:/data
    ports:
      - "8890:8890"
```

### How to create a backup

With [mu-cli](https://github.com/mu-semtech/mu-cli) installed and the Virtuoso service named `triplestore` in your project, run:

```sh
mu script triplestore create-backup
```

The backup is stored in `data/db/backups` in your project.

### How to restore a backup

A backup stored in `data/db/backups` can be restored via a separate container or via an environment variable.

The existing database data must be removed before restoring a backup:

```sh
rm data/db/virtuoso.{db,trx,pxa} data/db/virtuoso-temp.db data/db/.dba_pwd_set data/db/.backup_restored
```

Caveat: the restore commands take a backup prefix, which is the whole filename up to (but not including) the ending number and filename extension. For example, for a backup containing the file `virtuoso_backup_240822T0200-101.bp`, the prefix is `virtuoso_backup_240822T0200-`.

#### Restoring in a separate container

Stop the running container and restore the backup from `data/db/backups` using a new container:

```sh
docker run --rm -it -v ./data/db:/data redpencil/virtuoso virtuoso-t +restore-backup backups/backup_ +configfile /data/virtuoso.ini
```

The new container will exit once the backup has been restored; you can then restart the original db container.

#### Restoring using an environment variable

A backup placed in `data/db/backups` can also be restored by setting `BACKUP_PREFIX`. The backup is loaded automatically on startup, so no separate container is needed:

```sh
docker run --name my-virtuoso \
            -p 8890:8890 \
            -p 1111:1111 \
            -e DBA_PASSWORD=dba \
            -e SPARQL_UPDATE=true \
            -e BACKUP_PREFIX=backup_ \
            -v ./data/db:/data \
            -d redpencil/virtuoso
```

The backup will be ingested only once.

### How to dump all quads

With [mu-cli](https://github.com/mu-semtech/mu-cli) installed, run:

```sh
mu script triplestore maintenance dump_quads
```

The dumps are written to `data/db/dumps`.

### How to (re)load quads

Quads can be loaded automatically on startup, or manually.

#### Automatically on startup

By default, any data put in the `toLoad` directory in the Virtuoso database folder (`./data/db/toLoad`) is automatically loaded into Virtuoso on the first startup of the Docker container.

The load only runs on the initial start of the container. To trigger it again on the next startup, remove the `.data_loaded` marker and restart the container:

```sh
rm data/db/.data_loaded
docker compose restart triplestore
```

Files already in `toLoad` are loaded again, so remove them from `toLoad` first if you only want the new data loaded.

#### Manually

Make the quad `.nq` files available in `./data/db/dumps`. The quad files might be compressed. Enter the Virtuoso docker, open ISQL, register and run the load:

```sh
docker exec -it my-virtuoso bash
isql-v -U dba -P $DBA_PASSWORD
SQL> ld_dir('dumps', '*.nq', 'http://foo.bar');
SQL> rdf_loader_run();
SQL> checkpoint;
SQL> checkpoint_interval(N);
SQL> scheduler_interval(M);
```

> Note: **N** and **M** should be fetched from your `virtuoso.ini` config by looking for **CheckpointInterval** and **SchedulerInterval** respectively.

Validate the `ll_state` of the load. If `ll_state` is 2, the load completed:

```sql
select * from DB.DBA.load_list;
```

For more information, see http://virtuoso.openlinksw.com/dataspace/doc/dav/wiki/Main/VirtBulkRDFLoader.

### How to build the image from a specific commit

The image is built from a specific commit of [virtuoso-opensource](https://github.com/openlink/virtuoso-opensource). Pass the commit id as the `VIRTUOSO_COMMIT` [build argument](https://docs.docker.com/engine/reference/commandline/build/#set-build-time-variables---build-arg):

```sh
docker build --build-arg VIRTUOSO_COMMIT=<commit-sha> -t redpencil/virtuoso .
```

Without the build argument, the default commit `ad6589ff38488183a35dfe8ba398233c3380b5ba` (Virtuoso 7.2.17) is used. On `linux/arm64` the GeoSPARQL plugins (PROJ/GEOS) are not built; the build logs `not building geo plugins on arm`.

### How to upgrade Virtuoso

There are multiple ways of upgrading your Virtuoso version. The procedure described here takes a bit longer, but uses all of the latest features of your new Virtuoso version and optimizes your DB size on disk.

> **NOTE:** Upgrading Virtuoso is a procedure to be done with great care. Make sure you have backups before starting.

**1. Dump the quads.**
When upgrading it's recommended (and sometimes required!) to first dump the quads. With [mu-cli](https://github.com/mu-semtech/mu-cli) installed:

```sh
mu script triplestore maintenance dump_quads
```

**2. Stop the triplestore.**

```sh
docker compose stop triplestore
```

**3. Move the dumps to the `toLoad` folder.**

```sh
mv data/db/dumps/* data/db/toLoad
```

**4. Remove the old database.**

```sh
rm -f data/db/virtuoso.{db,trx,pxa} data/db/virtuoso-temp.db data/db/.data_loaded data/db/.dba_pwd_set
```

Consider truncating or removing `data/db/virtuoso.log` as well.

**5. Update the Virtuoso version** in `docker-compose.yml`:

```diff
   triplestore:
-    image: redpencil/virtuoso:1.0.0
+    image: redpencil/virtuoso:1.4.0
```

**6. Start the triplestore** and monitor the logs; importing the nquads might take a long time.

```sh
docker compose up -d triplestore
docker compose logs -f triplestore
```

After that your application can be started again and you should be good to go.

## Reference

### Ports

| Port | Service |
|---|---|
| 8890 | HTTP server, including the SPARQL endpoint at `/sparql` |
| 1111 | ODBC/SQL server (ISQL) |

### Data folders

The image symlinks `/data` to Virtuoso's database directory. Inside `/data`:

| Path | Description |
|---|---|
| `virtuoso.ini` | Configuration file, created from the image's default on first start. |
| `dumps/` | Created on startup; target folder of `dump_nquads`. |
| `toLoad/` | Files in this folder are loaded on the first startup (see [How to (re)load quads](#how-to-reload-quads)). |
| `backups/` | Backups created by `create-backup`, and source of `BACKUP_PREFIX` restores. |

### Environment variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `DBA_PASSWORD` | string | `dba` | Password set for the `dba` user on first startup. |
| `SPARQL_UPDATE` | string | unset | Set to `true` to grant `SPARQL_UPDATE` to the `SPARQL` user. |
| `DEFAULT_GRAPH` | string | `http://localhost:8890/DAV` | Graph into which `toLoad` files are loaded on first startup. |
| `ENABLE_CORS` | string | unset | Any value enables basic CORS headers on `/sparql`. Not set means no CORS headers. |
| `BACKUP_PREFIX` | string | unset | Backup prefix in `/data/backups` to restore once, at startup. |
| `VIRT_<Section>_<Key>` | string | from `virtuoso.ini` | Overrides a property of `virtuoso.ini`, see [`virtuoso.ini` overrides](#virtuosoini-overrides). |

Note that `DBA_PASSWORD`, `SPARQL_UPDATE`, `ENABLE_CORS` and `VIRT_*` settings are applied only once, on the first startup of a given `/data` folder (guarded by `.dba_pwd_set` and `/settings/.config_set`). To apply changes, remove the corresponding marker files or recreate the database folder.

### `virtuoso.ini` overrides

Any property in [`virtuoso.ini`](virtuoso.ini) can be overridden by an environment variable named `VIRT_<Section>_<Key>`, where `<Section>` and `<Key>` are case sensitive and CamelCased as in the ini file. The value is written to `virtuoso.ini` with `crudini`. For example, property `ErrorLogFile` in the `Database` section is configured as:

```yaml
environment:
  VIRT_Database_ErrorLogFile: "error.log"
```

Examples:

| Environment variable | Ini location |
|---|---|
| `VIRT_Database_ErrorLogFile=error.log` | `[Database] ErrorLogFile` |
| `VIRT_HTTPServer_ServerPort=8890` | `[HTTPServer] ServerPort` |
| `VIRT_Parameters_CheckpointInterval=60` | `[Parameters] CheckpointInterval` |
| `VIRT_SPARQL_ResultSetMaxRows=10000` | `[SPARQL] ResultSetMaxRows` |

Common sections in the bundled `virtuoso.ini` include `[Database]`, `[Parameters]`, `[HTTPServer]`, `[SPARQL]` and `[Plugins]`. The ini is rewritten in place on first startup only; later starts reuse the existing `/data/virtuoso.ini`.

### Startup behaviour

The container entrypoint (`virtuoso.sh`) performs, in order:

1. Creates `dumps/` and copies `virtuoso.ini` into `/data` if absent.
2. Applies `VIRT_*` environment variables to `virtuoso.ini` on first start (marker `/settings/.config_set`).
3. Restores the backup named by `BACKUP_PREFIX` from `backups/` once (marker `.backup_restored`).
4. On first start, sets the `dba` password, grants `SPARQL_UPDATE` when enabled, and loads the `dump_nquads` procedure (marker `.dba_pwd_set`).
5. Loads files from `toLoad/` once (marker `.data_loaded`).
6. Applies the `SPARQL_UPDATE` user-rights workaround when `SPARQL_UPDATE=true`.
7. Enables CORS on `/sparql` when `ENABLE_CORS` is set.
8. Starts `virtuoso-t +wait +foreground`.

## Contributing

Contributions to this repository are welcome, please create a pull request on the master branch.

New features will be tested on `redpencil/virtuoso:latest` first. Once the image is verified, version branches will be rebased on master.

# Engineering Reflection

## reload vs restart in Phase 4

### When is reload the correct choice?

`systemctl reload` sends a signal to the running process (typically `SIGHUP`) telling it to re-read its configuration without stopping. It is the correct choice when:

- The change being deployed is **configuration only** (for example, an updated `.env` file or a config JSON the process reads at startup) and the binary itself has not changed.
- The process **explicitly handles `SIGHUP`** and knows how to apply new config to its running state without a full restart.
- You want to avoid dropping in-flight connections, because the process PID stays alive throughout.

### When is restart required?

`systemctl restart` stops the old process and starts a fresh one. It is required when:

- The **application code has changed**: a new `server.js`, updated `node_modules`, or any file the Node.js process loaded at startup. Node.js does not hot-reload module code. Once a module is `require()`'d it is cached in memory for the lifetime of the process.
- The change affects the **listen port, TLS certificates, or other resources** that are acquired at startup and cannot be re-acquired without a full stop/start cycle.
- The process **does not handle `SIGHUP`**. Node.js by default does nothing when it receives `SIGHUP`, so `reload` would be a no-op and the old code would keep running.

### What would need to be true about kk-api for reload to work?

For `reload` to be a valid alternative in this script, all of the following would have to be true:

1. **The process listens for `SIGHUP` and acts on it.** Node.js does not do this by default. The application code would need an explicit handler, for example:

    ```js
    process.on('SIGHUP', () => {
    	reloadConfig();
    });
    ```

2. **The deployment only changes config, not code.** If `deploy_artifact` copies a new `server.js` or updated dependencies, `reload` would leave the old code running in memory. The new files on disk would be ignored.

3. **The reload handler completes atomically and correctly.** If the handler is partial or throws, the process could end up in a mixed state with some old config and some new config applied.

**Conclusion for this script:** `deploy_artifact` copies an entirely new version of the application, including a new `server.js` and potentially new `node_modules`. That means `restart` is required. The colleague's suggestion would only be valid for a config-only update where no code files change.

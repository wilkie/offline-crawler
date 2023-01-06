if (!window.__offline_replaced) {
  window.__offline_replaced = true;

  try {
      window.__localStorage = window.localStorage;
      window.__sessionStorage = window.sessionStorage;
      window.__indexedDB = window.indexedDB;
  }
  catch {
  }

  function callApi(method, path, data) {
    let args = path.split('/');
    let call = args[0];
    let response = null;

    try {
      console.log("[api]", path);
      if (call === "user_progress") {
        response = {
          signedIn: false
        };
      }
      else if (call === "v1") {
        call = args[1];
        args = args.slice(1);

        if (call === "users" && args[1] === "current") {
          response = {
            is_signed_in: false
          };
        }
      }
      else if (call === "example_solutions") {
        response = [];
      }
      else if (call === "hidden_lessons") {
        response = [];
      }
      else if (call === "user_app_options") {
        response = {
          signedIn: false,
          channel: "blah",
          reduceChannelUpdates: false
        };
      }
      else if (call === "channels") {
        // Get channel metadata

        // Maintain channel id
        window.__channel = args[1];
        let updated = window.localStorage.getItem("__channel_" + window.__channel + "_updated");
        let thumbnail = window.localStorage.getItem("__channel_" + window.__channel + "_thumbnail");
        let projectType = window.localStorage.getItem("__channel_" + window.__channel + "_projectType");
        let level = window.localStorage.getItem("__channel_" + window.__channel + "_level");

        // Default response (on initial load)
        let date = (new Date()).toISOString();
        response = {
          "hidden": true,
          "createdAt": date,
          "updatedAt": date,
          "id": args[1],
          "isOwner": true,
          "publishedAt": null,
          "projectType": null
        }

        // If we have written to it before, say it is in S3
        if (updated) {
          response.migratedToS3 = true;
        }

        if (thumbnail) {
          response.thumbnailUrl = thumbnail;
        }

        if (projectType) {
          response.projectType = projectType;
        }

        if (level) {
          response.level = level;
        }
      }
      else if (call === "sources" || call === "files") {
        // Get saved progress
        let filename = args.slice(1).join("/");
        let basename = args[args.length - 1].split('?')[0];

        if (basename === "versions") {
          // Get the version history of a file
          filename = args.slice(1, args.length - 1).join("/");
          console.log("[api] reading versions for file:", filename);
          let versions = JSON.parse(
            window.localStorage.getItem(call + "/" + filename + "/versions") || "[]"
          );
          let latest = window.localStorage.getItem(call + "/" + filename + "/latest");

          // Mark latest
          for (let i = 0; i < versions.length; i++) {
            if (versions[i].versionId == latest) {
              versions[i].isLatest = true;
            }

            versions[i].isLatest = false;
          }

          response = versions;
        }
        else if (basename === "restore") {
          // Restore level to particular version
          // It does this by storing the version record again at the head of the
          // version list.
          let restore = args[args.length - 1].split('?')[1].split('=')[1];
          console.log("[api] restoring", restore);

          let version = Math.random().toString().substring(2);
          let versions = JSON.parse(
              window.localStorage.getItem(call + "/" + filename + "/versions") || "[]"
          );
          let modified = (new Date()).toISOString();
          versions.push({
            versionId: version,
            lastModified: modified
          });
          window.localStorage.setItem(call + "/" + filename + "/versions", JSON.stringify(versions));
          window.localStorage.setItem(call + "/" + filename + "/latest", version);
        }
        else if (method === "GET") {
          // Retrieve file
          console.log("[api] reading file at path:", filename);

          // Negotiate version
          let latest = window.localStorage.getItem(call + "/" + filename + "/latest");
          response = window.localStorage.getItem(call + "/" + filename + "/versions/" + latest);
        }
        else {
          // Store file
          console.log("[api] writing file at path:", filename, data);

          // Remove the channel name
          let itemPath = filename.split('/').slice(1).join('/');

          // Detect if we are writing a thumbnail
          let category = "application";
          if (data.arrayBuffer) {
            category = "image";
            data = "";
            window.localStorage.setItem("__channel_" + window.__channel + "_thumbnail", "/v3/" + path);
          }

          // Add a version
          let version = Math.random().toString().substring(2);
          window.localStorage.setItem(call + "/" + filename + "/versions/" + version, data);
          let versions = JSON.parse(
              window.localStorage.getItem(call + "/" + filename + "/versions") || "[]"
          );
          let modified = (new Date()).toISOString();
          versions.push({
            versionId: version,
            lastModified: modified
          });
          window.localStorage.setItem(call + "/" + filename + "/versions", JSON.stringify(versions));
          window.localStorage.setItem(call + "/" + filename + "/latest", version);

          // Update channel
          window.localStorage.setItem("__channel_" + window.__channel + "_updated", "true");

          // Report the version
          response = {
            filename: itemPath,
            category: category,
            size: data.byteLength || data.length,
            versionId: version,
            timestamp: modified
          };
        }
      }
    }
    catch(e) {
      console.error("[api]" + e);
    }

    return response;
  }

  // Disable sessionStorage
  let sessionStorage = {};
  window.__defineGetter__('sessionStorage', function() {
    return {
      getItem: function(key) {
        console.log("[persist] sessionStorage.get", key);
        if (window.__sessionStorage) {
          return window.__sessionStorage.getItem(key);
        }
        else if (key in sessionStorage) {
          return sessionStorage[key];
        }
        else
        {
          return null;
        }
      },
      setItem: function(key, value) {
        console.log("[persist] sessionStorage.set", key, value);
        if (window.__sessionStorage) {
          return window.__sessionStorage.setItem(key, value);
        }
        return sessionStorage[key] = value;
      },
      removeItem: function(key) {
        if (window.__sessionStorage) {
          return window.__sessionStorage.removeItem(key);
        }
        delete sessionStorage[key];
      }
    };
  });

  // Disable localStorage
  let localStorage = {};
  window.__defineGetter__('localStorage', function() {
    return {
      getItem: function(key) {
        console.log("[persist] localStorage.get", key);
        if (window.__localStorage) {
          return window.__localStorage.getItem(key);
        }
        else if (key in localStorage) {
          return localStorage[key];
        }
        else
        {
          return null;
        }
      },
      setItem: function(key, value) {
        console.log("[persist] localStorage.set", key, value);
        if (window.__localStorage) {
          return window.__localStorage.setItem(key, value);
        }
        return localStorage[key] = value;
      },
      removeItem: function(key) {
        if (window.__localStorage) {
          return window.__localStorage.removeItem(key);
        }
        delete localStorage[key];
      }
    };
  });

  // Disable cookies
  document.__defineGetter__('cookie', function() { console.log("[persist] cookie.get"); return '' });
  document.__defineSetter__('cookie', function(v) { console.log("[persist] cookie.set", v); });

  window.addEventListener('load', () => {
    var userAgent = navigator.userAgent.toLowerCase();
    if (userAgent.indexOf(' electron/') > -1) {
      // This is an electron app.
    }

    // Make sure we re-write the header links
    // Select the node that will be observed for mutations
    const targetNode = document.querySelector('.header_level');

    // Options for the observer (which mutations to observe)
    const config = { attributes: true, childList: true, subtree: true };

    // Callback function to execute when mutations are observed
    const callback = (mutationList, observer) => {
      for (const mutation of mutationList) {
        if (mutation.type === 'childList') {
          // The header was built... modify the links
          targetNode.querySelectorAll('a').forEach( (link) => {
            let url = link.getAttribute('href');
            if (url) {
              if (url.startsWith("//localhost-studio.code.org:3000")) {
                url = "/" + url.split(':').slice(1).join(':').split('/').slice(1).join('/');
              }
              if (url[0] === "/") {
                url = "../../../../.." + url;
              }
              if (!url.endsWith(".html")) {
                url = url + ".html";
              }
              link.setAttribute('href', url);
            }
          });
        //} else if (mutation.type === 'attributes') {
        }
      }
    };

    // Create an observer instance linked to the callback function
    const observer = new MutationObserver(callback);

    callback([{type: 'childList'}], observer);

    // Start observing the target node for configured mutations
    observer.observe(targetNode, config);
  });

  // Ensure absolute paths get turned into relative paths
  let oldXHR = XMLHttpRequest;
  window.XMLHttpRequest = function() {
    let ret = new oldXHR(arguments);
    let oldOpen = ret.open;
    ret.open = function(method, url, async, user, password) {
      // Deal with the weird proxy stuff via 'media?u='
      // stuff like: studio.learningequality.org/media?u=https%3A%2F%2Fstudi...
      let idx = url.indexOf("media?u");
      if (idx > 0) {
        idx += 8;
        url = decodeURIComponent(url.substring(idx));
      }

      // Now overwrite the code.org urls
      let domains = [
        "https://studio.code.org",
        "https://code.org",
      ];

      for (let i = 0; i < domains.length; i++) {
        let domain = domains[i];
        if (url.startsWith(domain)) {
          url = url.substring(domain.length);
          break;
        }
      }

      if (url[0] === "/") {
        url = "../../../../.." + url;
      }
      arguments[1] = url;

      let oldSend = ret.send;
      ret.send = function(data) {
        let response = null;
        let path = url;

        if (url.startsWith("../../../../../api/")) {
          path = url.substring("../../../../../api/".length);
          response = callApi(method, path, data);
        }

        if (url.startsWith("../../../../../v3/")) {
          path = url.substring("../../../../../v3/".length);
          response = callApi(method, path, data);
        }

        try {
          if (response) {
            let headers = {
              "content-type": "application/json"
            };
            let rHeaders = {};
            ret.setRequestHeader = function(header, value) {
              rHeaders[header] = value;
            };
            ret.getResponseHeader = function(header) {
              header = header.toLowerCase();
              return headers[header];
            };
            ret.getAllResponseHeaders = function() {
              let headerString = "";
              for (const header of Object.keys(headers)) {
                let value = ret.getResponseHeader(header);
                headerString = headerString + header + ": " + value + "\r\n";
              }
              return headerString;
            };
            ret.__defineGetter__('response', function() {
              return response;
            });
            ret.__defineGetter__('status', function() {
              if (response === 404) {
                return 404;
              }
              return 200;
            });
            ret.__defineGetter__('statusText', function() {
              if (response === 404) {
                return "Not found";
              }
              return "OK";
            });
            ret.__defineGetter__('readyState', function() {
              return 4;
            });
            let text = JSON.stringify(response);
            ret.__defineGetter__('responseText', function() {
              return text;
            });

            console.log("[api]", path.split('/')[0], ret.response);

            let ev = new ProgressEvent("load");
            ev.total = text.length;
            ev.loaded = ev.total;
            ev.lengthComputable = true;
            let rscev = new Event("readystatechange");

            ret.dispatchEvent(ev);
            ret.dispatchEvent(rscev);
            return;
          }
        }
        catch (e) {
          console.error("[api]" + e);
        }

        return oldSend.bind(this)(arguments);
      };

      return oldOpen.bind(this)(method, url, async, user, password);
    };

    return ret;
  };

  // Same for fetch()
  let oldFetch = window.fetch;
  window.fetch = function(url, options) {
    if (url[0] === "/") {
      url = "../../../../.." + url;
    }
    return oldFetch(url, options);
  };

  // Now we do some magic when images are loaded via <img> / <svg>
  let oldSANS = window.Element.prototype.setAttributeNS;
  window.Element.prototype.setAttributeNS = function(namespace, name, url) {
    if (name === "xlink:href" && url[0] === "/") {
      url = "../../../../.." + url;
    }
    return oldSANS.bind(this)(namespace, name, url);
  };
  let oldSA = window.Element.prototype.setAttribute;
  window.Element.prototype.setAttribute = function(name, url) {
    if (name === "src" && url[0] === "/") {
      url = "../../../../.." + url;
    }
    if (name === "href" && url[0] === "/") {
      url = "../../../../.." + url;
    }
    return oldSA.bind(this)(name, url);
  };

  // For "Image()" functions (like in Phaser)
  let types = [
    window.Image,
    window.Element,
    window.HTMLElement,
    window.HTMLScriptElement,
    window.HTMLImageElement
  ];

  for (let i = 0; i < types.length; i++) {
    let prototype = types[i].prototype;
    let oldSrc = prototype.__lookupSetter__('src');
    prototype.__defineSetter__('src', function(url) {
      if (url[0] === "/") {
        url = "../../../../.." + url;
      }
      // Also allows the image to be used inside unsafe contexts such as, of
      // course, a webgl texture!
      this.crossOrigin = "anonymous";
      oldSrc.bind(this)(url);
    });
  }
}

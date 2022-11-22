if (!window.__offline_replaced) {
  window.__offline_replaced = true;

  // Disable sessionStorage
  window.__defineGetter__('sessionStorage', function() {
    return {
      getItem: function(key) { return undefined; },
      setItem: function(key, value) { return undefined; }
    };
  });

  // Disable localStorage
  let localStorage = {};
  window.__defineGetter__('localStorage', function() {
    return {
      getItem: function(key) { if (key in localStorage) { return localStorage[key]; } else { return null; } },
      setItem: function(key, value) { console.log("setting", key, value); return localStorage[key] = value; },
      removeItem: function(key) { delete localStorage[key]; }
    };
  });

  // Disable cookie
  document.__defineGetter__('cookie', function() { return '' });
  document.__defineSetter__('cookie', function(v) {});

  window.addEventListener('load', () => {
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
      if (url[0] === "/") {
        url = "../../../../.." + url;
      }
      arguments[1] = url;
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
    return oldSA.bind(this)(name, url);
  };

  // For "Image()" functions (like in Phaser)
  let oldImageSrc = window.Image.prototype.__lookupSetter__('src');
  window.Image.prototype.__defineSetter__('src', function(url) {
    if (url[0] === "/") {
      url = "../../../../.." + url;
    }
    // Also allows the image to be used inside unsafe contexts such as, of
    // course, a webgl texture!
    this.crossOrigin = "anonymous";
    oldImageSrc.bind(this)(url);
  });
}

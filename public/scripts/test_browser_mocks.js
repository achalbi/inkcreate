(function() {
  if (window.__inkcreateBrowserMocksInstalled) {
    return;
  }

  window.__inkcreateBrowserMocksInstalled = true;
  window.__inkcreateTestNotifications = [];

  if (!navigator.mediaDevices) {
    navigator.mediaDevices = {};
  }

  if (!navigator.permissions) {
    navigator.permissions = {};
  }

  navigator.permissions.query = async function() {
    return { state: "granted" };
  };

  navigator.mediaDevices.getUserMedia = async function() {
    return {
      getTracks() {
        return [{
          stop() {}
        }];
      }
    };
  };

  class MockMediaRecorder extends EventTarget {
    constructor(stream, options = {}) {
      super();
      this.stream = stream;
      this.mimeType = options.mimeType || "audio/webm";
      this.state = "inactive";
    }

    start() {
      this.state = "recording";
    }

    stop() {
      this.state = "inactive";
      const blob = new Blob(["mock voice note"], { type: this.mimeType });
      window.setTimeout(() => {
        this.dispatchEvent(new MessageEvent("dataavailable", { data: blob }));
        this.dispatchEvent(new Event("stop"));
      }, 0);
    }

    static isTypeSupported() {
      return true;
    }
  }

  window.MediaRecorder = MockMediaRecorder;

  class MockNotification {}

  Object.defineProperty(MockNotification, "permission", {
    configurable: true,
    enumerable: true,
    get() {
      return "granted";
    }
  });

  MockNotification.requestPermission = async function() {
    return "granted";
  };

  window.Notification = MockNotification;
  globalThis.Notification = MockNotification;

  let currentSubscription = null;

  const registration = {
    pushManager: {
      async getSubscription() {
        return currentSubscription;
      },

      async subscribe() {
        currentSubscription = {
          endpoint: "https://example.test/push/subscription/1",
          toJSON() {
            return {
              endpoint: this.endpoint,
              keys: {
                p256dh: "mock-p256dh-key",
                auth: "mock-auth-key"
              }
            };
          },
          async unsubscribe() {
            currentSubscription = null;
            return true;
          }
        };

        return currentSubscription;
      }
    },

    async showNotification(title, options = {}) {
      window.__inkcreateTestNotifications.push({ title, options });
    },

    async getNotifications() {
      return [];
    },

    async update() {}
  };

  window.__inkcreatePushTestRegistration = registration;

  navigator.serviceWorker = {
    ready: Promise.resolve(registration),
    async register() {
      return registration;
    }
  };
})();

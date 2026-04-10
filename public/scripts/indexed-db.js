const DB_NAME = "inkcreate-pwa";
const DB_VERSION = 3;
const STORES = {
  drafts: "draftCaptures",
  uploads: "pendingUploads",
  syncEvents: "syncEvents",
  preferences: "appPreferences"
};

function openDatabase() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onupgradeneeded = () => {
      const db = request.result;

      Object.values(STORES).forEach((storeName) => {
        if (!db.objectStoreNames.contains(storeName)) {
          db.createObjectStore(storeName, { keyPath: "id" });
        }
      });
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function transact(storeName, mode, operation) {
  const db = await openDatabase();

  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, mode);
    const store = tx.objectStore(storeName);
    let result;
    let settled = false;
    const request = operation(store);

    const resolveOnce = (value) => {
      if (settled) {
        return;
      }

      settled = true;
      resolve(value);
    };

    const rejectOnce = (error) => {
      if (settled) {
        return;
      }

      settled = true;
      reject(error);
    };

    request.onsuccess = () => {
      result = request.result;
    };
    request.onerror = () => rejectOnce(request.error);
    tx.oncomplete = () => resolveOnce(result);
    tx.onerror = () => rejectOnce(tx.error || request.error);
    tx.onabort = () => rejectOnce(tx.error || new DOMException("IndexedDB transaction aborted", "AbortError"));
  });
}

export const localStore = {
  stores: STORES,

  async put(storeName, value) {
    return transact(storeName, "readwrite", (store) => store.put(value));
  },

  async get(storeName, id) {
    return transact(storeName, "readonly", (store) => store.get(id));
  },

  async getAll(storeName) {
    return transact(storeName, "readonly", (store) => store.getAll());
  },

  async delete(storeName, id) {
    return transact(storeName, "readwrite", (store) => store.delete(id));
  }
};

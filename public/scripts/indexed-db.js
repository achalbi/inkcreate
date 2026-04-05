const DB_NAME = "inkcreate-pwa";
const DB_VERSION = 2;
const STORES = {
  drafts: "draftCaptures",
  uploads: "pendingUploads",
  syncEvents: "syncEvents"
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
    const request = operation(store);

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export const localStore = {
  stores: STORES,

  async put(storeName, value) {
    return transact(storeName, "readwrite", (store) => store.put(value));
  },

  async getAll(storeName) {
    return transact(storeName, "readonly", (store) => store.getAll());
  },

  async delete(storeName, id) {
    return transact(storeName, "readwrite", (store) => store.delete(id));
  }
};

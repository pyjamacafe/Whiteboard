import type { BoardFolder, BoardMeta, SaveData, TrashEntry } from '../types/model';

export interface BoardIndex {
  boards: BoardMeta[];
  folders: BoardFolder[];
}

const DB_NAME = 'tissuebox-db-v1';
const DB_VERSION = 1;
const STORE_META = 'meta';
const STORE_BOARDS = 'boards';
const STORE_THUMBS = 'thumbs';
const RETENTION_MS = 30 * 24 * 3600 * 1000;

/**
 * Atomic IndexedDB persistence mirroring BoardStore.swift
 * (boards, folders, cached thumbnails, and 30-day Recently Deleted trash),
 * with automatic in-memory fallback for non-browser / Vitest environments.
 */
export class BoardStore {
  private dbPromise: Promise<IDBDatabase> | null = null;
  private memoryMeta = new Map<string, unknown>();
  private memoryBoards = new Map<string, SaveData>();
  private memoryThumbs = new Map<string, string>();
  private readonly useMemory: boolean;

  constructor(forceMemory = false) {
    this.useMemory = forceMemory || typeof indexedDB === 'undefined';
  }

  private openDB(): Promise<IDBDatabase> {
    if (this.dbPromise) return this.dbPromise;
    this.dbPromise = new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(STORE_META)) db.createObjectStore(STORE_META);
        if (!db.objectStoreNames.contains(STORE_BOARDS)) db.createObjectStore(STORE_BOARDS);
        if (!db.objectStoreNames.contains(STORE_THUMBS)) db.createObjectStore(STORE_THUMBS);
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
    return this.dbPromise;
  }

  private async idbGet<T>(storeName: string, key: string): Promise<T | undefined> {
    const db = await this.openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(storeName, 'readonly');
      const req = tx.objectStore(storeName).get(key);
      req.onsuccess = () => resolve(req.result as T | undefined);
      req.onerror = () => reject(req.error);
    });
  }

  private async idbPut<T>(storeName: string, key: string, value: T): Promise<void> {
    const db = await this.openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(storeName, 'readwrite');
      tx.objectStore(storeName).put(value, key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  }

  private async idbDelete(storeName: string, key: string): Promise<void> {
    const db = await this.openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(storeName, 'readwrite');
      tx.objectStore(storeName).delete(key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  }

  // MARK: - Index

  async loadIndex(): Promise<BoardIndex> {
    const raw = this.useMemory
      ? (this.memoryMeta.get('index') as BoardIndex | undefined)
      : await this.idbGet<BoardIndex>(STORE_META, 'index');
    if (!raw) return { boards: [], folders: [] };
    return {
      boards: [...(raw.boards ?? [])].sort((a, b) => b.modified - a.modified),
      folders: [...(raw.folders ?? [])],
    };
  }

  async saveIndex(index: BoardIndex): Promise<void> {
    if (this.useMemory) {
      this.memoryMeta.set('index', structuredClone(index));
      return;
    }
    await this.idbPut(STORE_META, 'index', index);
  }

  // MARK: - Board Content

  async loadBoard(id: string): Promise<SaveData | null> {
    if (this.useMemory) {
      const hit = this.memoryBoards.get(id);
      return hit ? structuredClone(hit) : null;
    }
    return (await this.idbGet<SaveData>(STORE_BOARDS, id)) ?? null;
  }

  async saveBoard(id: string, data: SaveData): Promise<void> {
    if (this.useMemory) {
      this.memoryBoards.set(id, structuredClone(data));
      return;
    }
    await this.idbPut(STORE_BOARDS, id, data);
  }

  async deleteBoardData(id: string): Promise<void> {
    if (this.useMemory) {
      this.memoryBoards.delete(id);
      return;
    }
    await this.idbDelete(STORE_BOARDS, id);
  }

  // MARK: - Thumbnails

  private thumbKey(boardId: string, isDark: boolean): string {
    return `${boardId}_${isDark ? 'dark' : 'light'}`;
  }

  async loadThumbnail(boardId: string, isDark: boolean): Promise<string | null> {
    const key = this.thumbKey(boardId, isDark);
    if (this.useMemory) return this.memoryThumbs.get(key) ?? null;
    return (await this.idbGet<string>(STORE_THUMBS, key)) ?? null;
  }

  async saveThumbnail(boardId: string, isDark: boolean, dataUrl: string): Promise<void> {
    const key = this.thumbKey(boardId, isDark);
    if (this.useMemory) {
      this.memoryThumbs.set(key, dataUrl);
      return;
    }
    await this.idbPut(STORE_THUMBS, key, dataUrl);
  }

  async invalidateThumbnails(boardId: string): Promise<void> {
    for (const isDark of [false, true]) {
      const key = this.thumbKey(boardId, isDark);
      if (this.useMemory) this.memoryThumbs.delete(key);
      else await this.idbDelete(STORE_THUMBS, key);
    }
  }

  // MARK: - 30-Day Trash

  async loadTrash(now = Date.now()): Promise<TrashEntry[]> {
    const raw = this.useMemory
      ? (this.memoryMeta.get('trash') as TrashEntry[] | undefined)
      : await this.idbGet<TrashEntry[]>(STORE_META, 'trash');
    const entries = raw ?? [];
    const cutoff = now - RETENTION_MS;
    const valid = entries.filter((e) => e.deletedAt > cutoff).sort((a, b) => b.deletedAt - a.deletedAt);
    if (valid.length !== entries.length) {
      await this.saveTrash(valid);
    }
    return valid;
  }

  private async saveTrash(entries: TrashEntry[]): Promise<void> {
    if (this.useMemory) {
      this.memoryMeta.set('trash', structuredClone(entries));
      return;
    }
    await this.idbPut(STORE_META, 'trash', entries);
  }

  async trashBoard(id: string, name: string, now = Date.now()): Promise<TrashEntry[]> {
    const data = (await this.loadBoard(id)) ?? { strokes: [], placedImages: [], fills: [], scenes: [] };
    await this.deleteBoardData(id);
    await this.invalidateThumbnails(id);
    const entries = await this.loadTrash(now);
    const updated: TrashEntry[] = [{ id, name, deletedAt: now, data }, ...entries];
    await this.saveTrash(updated);
    return updated;
  }

  async restoreBoard(
    trashId: string,
    newBoardId: string
  ): Promise<{ name: string; data: SaveData; remaining: TrashEntry[] } | null> {
    const entries = await this.loadTrash();
    const target = entries.find((e) => e.id === trashId);
    if (!target) return null;
    const data: SaveData = target.data ?? { strokes: [], placedImages: [], fills: [], scenes: [] };
    await this.saveBoard(newBoardId, data);
    const remaining = entries.filter((e) => e.id !== trashId);
    await this.saveTrash(remaining);
    return { name: target.name, data, remaining };
  }

  async permanentlyDeleteTrash(id: string): Promise<TrashEntry[]> {
    const entries = await this.loadTrash();
    const remaining = entries.filter((e) => e.id !== id);
    await this.saveTrash(remaining);
    return remaining;
  }

  async emptyTrash(): Promise<TrashEntry[]> {
    await this.saveTrash([]);
    return [];
  }
}

export const boardStore = new BoardStore();

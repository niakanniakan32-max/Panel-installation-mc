import { useEffect, useState } from 'react';
import { Dialog } from '@/elements/dialog';
import { Button } from '@/elements/button';
import Spinner from '@/elements/Spinner';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import {
    faSearch, faDownload, faArrowLeft, faChevronLeft, faChevronRight,
} from '@fortawesome/free-solid-svg-icons';

interface Modpack {
    id: string;
    name: string;
    summary: string;
    downloads: number;
    logo: string | null;
    author: string;
    provider: 'modrinth' | 'ftb' | 'curseforge';
    loader?: string;
    mcVersion?: string;
}

interface MpVersion {
    id: string;
    name: string;
    gameVersion: string;
    releaseType: number;
    loader: string;
    isServerPack?: boolean;
    serverPackFileId?: number | null;
    fileLength?: number | null;
}

const fmtSize = (bytes?: number | null): string => {
    if (!bytes) return '';
    const mb = bytes / 1024 / 1024;
    return mb >= 1024 ? `${(mb / 1024).toFixed(1)} GB` : `${Math.round(mb)} MB`;
};

interface Props {
    open: boolean;
    onClose: () => void;
    onSelect: (projectId: string, versionId: string, modpackName: string, provider?: string, mcVersion?: string, loader?: string) => void;
}

const PAGE_SIZE = 24;

const apiGet = (url: string): Promise<Response> =>
    fetch(url, {
        credentials: 'same-origin',
        headers: { 'X-Requested-With': 'XMLHttpRequest', Accept: 'application/json' },
    });

export default ({ open, onClose, onSelect }: Props) => {
    const [provider, setProvider] = useState<'modrinth' | 'ftb' | 'curseforge'>('modrinth');
    const [query, setQuery] = useState('');
    const [items, setItems] = useState<Modpack[]>([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');
    const [total, setTotal] = useState(0);
    const [page, setPage] = useState(1);
    const [pageInput, setPageInput] = useState('1');
    const [sortBy, setSortBy] = useState('downloads');
    const [picked, setPicked] = useState<Modpack | null>(null);
    const [versions, setVersions] = useState<MpVersion[]>([]);
    const [loadingVersions, setLoadingVersions] = useState(false);

    const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

    const runSearch = async (q: string, pageNum: number, prov: 'modrinth' | 'ftb' | 'curseforge', sort: string) => {
        setLoading(true);
        setError('');
        try {
            if (prov === 'modrinth') {
                const p = new URLSearchParams({
                    query: q, limit: String(PAGE_SIZE),
                    offset: String((pageNum - 1) * PAGE_SIZE), index: sort,
                });
                p.set('facets', '[["project_type:modpack"]]');
                const r = await fetch(`https://api.modrinth.com/v2/search?${p}`);
                if (!r.ok) throw new Error(`Modrinth HTTP ${r.status}`);
                const d = await r.json();
                setItems((d.hits || []).map((h: any) => ({
                    id: h.project_id, name: h.title, summary: h.description || '',
                    downloads: h.downloads || 0, logo: h.icon_url || null,
                    author: h.author || 'unknown', provider: 'modrinth',
                    loader: (h.loaders || [])[0] || '', mcVersion: (h.game_versions || [])[0] || '',
                })));
                setTotal(d.total_hits || 0);
            } else if (prov === 'curseforge') {
                const sortMap: Record<string, number> = { downloads: 2, newest: 3, updated: 4 };
                const p = new URLSearchParams({
                    q, page: String(pageNum - 1),
                    sortField: String(sortMap[sort] || 2), sortOrder: 'desc',
                });
                const r = await apiGet(`/api/client/modpacks/curseforge/search?${p}`);
                if (!r.ok) throw new Error(`CurseForge HTTP ${r.status}`);
                const d = await r.json();
                setItems((d.items || []).map((m: any) => ({
                    id: String(m.id), name: m.name, summary: m.summary || '',
                    downloads: m.downloads || 0, logo: m.logo || null,
                    author: (m.authors && m.authors[0]) || 'unknown', provider: 'curseforge',
                })));
                setTotal(d.total || 0);
            } else {
                const r = await apiGet('/api/client/modpacks/ftb-list');
                if (!r.ok) throw new Error(`FTB HTTP ${r.status}`);
                const d = await r.json();
                const all = (d.items || []).map((m: any) => ({
                    id: String(m.id), name: m.name, summary: m.summary || '',
                    downloads: m.installs || m.downloads || 0, logo: m.logo || null,
                    author: m.author || 'FTB', provider: 'ftb',
                }));
                const ql = q.toLowerCase();
                const filtered = ql ? all.filter((m: Modpack) => m.name.toLowerCase().includes(ql)) : all;
                setTotal(filtered.length);
                const s = (pageNum - 1) * PAGE_SIZE;
                setItems(filtered.slice(s, s + PAGE_SIZE));
            }
        } catch (e: any) {
            setError(e?.message || 'Search failed');
            setItems([]);
            setTotal(0);
        }
        setLoading(false);
    };

    useEffect(() => {
        if (!open) {
            setQuery(''); setItems([]); setPicked(null); setVersions([]);
            setPage(1); setPageInput('1'); setError('');
            return;
        }
        runSearch('', 1, provider, sortBy);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [open]);

    const switchProvider = (p: 'modrinth' | 'ftb' | 'curseforge') => {
        setProvider(p);
        setPage(1);
        setPageInput('1');
        setPicked(null);
        setVersions([]);
        runSearch(query, 1, p, sortBy);
    };

    const submitSearch = (e: React.FormEvent) => {
        e.preventDefault();
        setPage(1);
        setPageInput('1');
        runSearch(query, 1, provider, sortBy);
    };

    const goPage = (n: number) => {
        if (n < 1 || n > totalPages) return;
        setPage(n);
        setPageInput(String(n));
        runSearch(query, n, provider, sortBy);
    };

    const openVersions = async (m: Modpack) => {
        setPicked(m);
        setLoadingVersions(true);
        setVersions([]);
        try {
            if (m.provider === 'modrinth') {
                const r = await fetch(`https://api.modrinth.com/v2/project/${m.id}/version`);
                const d = await r.json();
                setVersions((d || []).map((v: any) => ({
                    id: v.id, name: v.name, gameVersion: (v.game_versions || [])[0] || 'unknown',
                    releaseType: v.version_type === 'release' ? 1 : 2, loader: (v.loaders || [])[0] || 'unknown',
                })));
            } else if (m.provider === 'curseforge') {
                const r = await apiGet(`/api/client/modpacks/curseforge/versions/${m.id}`);
                const d = await r.json();
                const list = (d.items || []).map((v: any) => ({
                    id: String(v.id), name: v.name, gameVersion: v.gameVersion || 'unknown',
                    releaseType: v.releaseType || 1, loader: v.loader || 'forge',
                    isServerPack: !!v.isServerPack, serverPackFileId: v.serverPackFileId ?? null,
                    fileLength: v.fileLength ?? null,
                }));
                // Recommended first: server packs on top, then newest
                list.sort((a: MpVersion, b: MpVersion) => Number(b.isServerPack || false) - Number(a.isServerPack || false));
                setVersions(list);
            } else {
                const r = await apiGet(`/api/client/modpacks/ftb-versions/${m.id}`);
                const d = await r.json();
                setVersions(d.items || []);
            }
        } catch {
            setVersions([]);
        }
        setLoadingVersions(false);
    };

    const pickVersion = async (v: MpVersion) => {
        if (!picked) return;
        if (picked.provider === 'curseforge') {
            try {
                const r = await apiGet(`/api/client/modpacks/curseforge/download/${picked.id}/${v.id}`);
                const d = await r.json();
                if (!d.url) throw new Error('no download url');
                onSelect(d.url, v.id, picked.name, 'curseforge', v.gameVersion, v.loader);
                onClose();
            } catch {
                alert('Could not get the CurseForge download link for this version.');
            }
            return;
        }
        onSelect(picked.id, v.id, picked.name, picked.provider, v.gameVersion, v.loader);
        onClose();
    };

    return (
        <Dialog open={open} onClose={onClose} title="Install Modpack" hideCloseButton>
            {!picked ? (
                <>
                    <div className="flex gap-2 mb-3">
                        <button
                            onClick={() => switchProvider('modrinth')}
                            className={`flex-1 px-3 py-2 rounded font-medium text-sm ${provider === 'modrinth' ? 'bg-green-600 text-white' : 'bg-neutral-700 text-neutral-300'}`}
                        >
                            Modrinth
                        </button>
                        <button
                            onClick={() => switchProvider('curseforge')}
                            className={`flex-1 px-3 py-2 rounded font-medium text-sm ${provider === 'curseforge' ? 'bg-orange-600 text-white' : 'bg-neutral-700 text-neutral-300'}`}
                        >
                            CurseForge
                        </button>
                        <button
                            onClick={() => switchProvider('ftb')}
                            className={`flex-1 px-3 py-2 rounded font-medium text-sm ${provider === 'ftb' ? 'bg-blue-600 text-white' : 'bg-neutral-700 text-neutral-300'}`}
                        >
                            FTB
                        </button>
                    </div>
                    <form onSubmit={submitSearch} className="flex gap-2 mb-2">
                        <input
                            type="text"
                            value={query}
                            onChange={e => setQuery(e.target.value)}
                            placeholder="Search modpacks..."
                            className="flex-1 bg-neutral-600 text-white px-3 py-2 rounded border border-neutral-500"
                        />
                        <select
                            value={sortBy}
                            onChange={e => { setSortBy(e.target.value); setPage(1); }}
                            className="bg-neutral-600 text-white px-2 py-2 rounded border border-neutral-500 text-sm"
                        >
                            <option value="downloads">Popular</option>
                            <option value="newest">Newest</option>
                            <option value="updated">Updated</option>
                        </select>
                        <Button type="submit">
                            <FontAwesomeIcon icon={faSearch} className="mr-2" />
                            Search
                        </Button>
                    </form>
                    {loading ? (
                        <div className="flex justify-center p-8"><Spinner size="large" /></div>
                    ) : (
                        <>
                            {error && (
                                <div className="bg-red-900/40 border border-red-500 rounded p-3 text-red-300 text-sm mb-3">
                                    Error: {error}
                                </div>
                            )}
                            {items.length === 0 ? (
                                <p className="text-neutral-400 text-center p-8">No modpacks found.</p>
                            ) : (
                                <>
                                    <div className="grid grid-cols-1 md:grid-cols-2 gap-3 max-h-96 overflow-y-auto pr-1">
                                        {items.map(m => (
                                            <div
                                                key={`${m.provider}-${m.id}`}
                                                onClick={() => openVersions(m)}
                                                className="bg-neutral-700 rounded-xl p-4 cursor-pointer border-2 border-transparent hover:border-blue-500 hover:shadow-lg hover:shadow-blue-900/30 transition-all"
                                            >
                                                <div className="flex items-start gap-3 mb-2">
                                                    {m.logo && <img src={m.logo} className="w-14 h-14 rounded-lg flex-shrink-0 ring-1 ring-neutral-600" alt="" />}
                                                    <div className="flex-1 min-w-0">
                                                        <h3 className="text-white font-semibold truncate">{m.name}</h3>
                                                        <p className="text-xs text-neutral-400">by {m.author}</p>
                                                        <div className="flex items-center gap-2 mt-1 flex-wrap">
                                                            <span className="text-[11px] bg-neutral-600 text-neutral-200 px-2 py-0.5 rounded-full">
                                                                {m.downloads.toLocaleString()} downloads
                                                            </span>
                                                            {m.loader && (
                                                                <span className="text-[11px] bg-blue-900/60 text-blue-200 px-2 py-0.5 rounded-full">
                                                                    {m.loader}{m.mcVersion ? ` • ${m.mcVersion}` : ''}
                                                                </span>
                                                            )}
                                                        </div>
                                                    </div>
                                                </div>
                                                <p className="text-sm text-neutral-300 line-clamp-2 min-h-10">{m.summary}</p>
                                                <Button onClick={(e) => { e.stopPropagation(); openVersions(m); }} className="mt-2 w-full text-sm">
                                                    Install
                                                </Button>
                                            </div>
                                        ))}
                                    </div>
                                    <div className="flex items-center justify-center gap-2 mt-4 text-sm">
                                        <Button.Text onClick={() => goPage(page - 1)} disabled={page <= 1}>
                                            <FontAwesomeIcon icon={faChevronLeft} className="mr-1" /> Prev
                                        </Button.Text>
                                        <span className="text-neutral-400">Page {page} / {totalPages}</span>
                                        <Button.Text onClick={() => goPage(page + 1)} disabled={page >= totalPages}>
                                            Next <FontAwesomeIcon icon={faChevronRight} className="ml-1" />
                                        </Button.Text>
                                        <form
                                            onSubmit={(e) => {
                                                e.preventDefault();
                                                const n = parseInt(pageInput, 10);
                                                if (!isNaN(n)) goPage(n);
                                            }}
                                            className="flex items-center gap-1 ml-2"
                                        >
                                            <input
                                                type="number" min="1" max={totalPages} value={pageInput}
                                                onChange={e => setPageInput(e.target.value)}
                                                className="w-16 bg-neutral-600 text-white px-2 py-1 rounded border border-neutral-500 text-sm"
                                            />
                                        </form>
                                    </div>
                                </>
                            )}
                        </>
                    )}
                </>
            ) : (
                <>
                    <div className="mb-4 flex items-center gap-3">
                        <Button.Text onClick={() => { setPicked(null); setVersions([]); }}>
                            <FontAwesomeIcon icon={faArrowLeft} className="mr-2" />
                            Back
                        </Button.Text>
                        {picked.logo && <img src={picked.logo} className="w-10 h-10 rounded" alt="" />}
                        <div>
                            <h3 className="text-white font-semibold">{picked.name}</h3>
                            <p className="text-xs text-neutral-400">Select a version to install</p>
                        </div>
                    </div>
                    {loadingVersions ? (
                        <div className="flex justify-center p-8"><Spinner size="large" /></div>
                    ) : versions.length === 0 ? (
                        <p className="text-neutral-400 text-center p-8">No versions available.</p>
                    ) : (
                        <>
                            {picked.provider === 'curseforge' && versions.some(v => v.isServerPack) && (
                                <div className="bg-green-900/30 border border-green-600 rounded p-3 text-sm text-green-200 mb-3">
                                    Recommended: pick a version with the <strong>SERVER PACK</strong> badge — it installs faster
                                    and skips client-only files. Only use a client version if its server pack is broken.
                                </div>
                            )}
                            <div className="max-h-96 overflow-y-auto space-y-2 pr-1">
                                {versions.map(v => (
                                    <div
                                        key={v.id}
                                        onClick={() => pickVersion(v)}
                                        className={`rounded-lg p-3 flex items-center justify-between cursor-pointer border-2 ${
                                            v.isServerPack
                                                ? 'bg-green-900/20 border-green-600 hover:border-green-400'
                                                : 'bg-neutral-700 border-transparent hover:border-blue-500'
                                        }`}
                                    >
                                        <div className="flex-1 min-w-0">
                                            <p className="text-white font-medium flex items-center gap-2 flex-wrap">
                                                <span className="truncate">{v.name}</span>
                                                {v.isServerPack ? (
                                                    <span className="text-[11px] font-bold bg-green-600 text-white px-2 py-0.5 rounded whitespace-nowrap">
                                                        SERVER PACK • Recommended
                                                    </span>
                                                ) : v.serverPackFileId ? (
                                                    <span className="text-[11px] bg-neutral-600 text-neutral-200 px-2 py-0.5 rounded whitespace-nowrap">
                                                        Client files
                                                    </span>
                                                ) : null}
                                                {v.releaseType !== 1 && (
                                                    <span className="text-[11px] bg-amber-600 text-white px-2 py-0.5 rounded whitespace-nowrap">
                                                        Beta
                                                    </span>
                                                )}
                                            </p>
                                            <p className="text-xs text-neutral-400 mt-1">
                                                MC {v.gameVersion} • {v.loader}
                                                {v.fileLength ? ` • ${fmtSize(v.fileLength)}` : ''}
                                            </p>
                                        </div>
                                        <Button className="ml-3 flex-shrink-0">
                                            <FontAwesomeIcon icon={faDownload} className="mr-2" />
                                            Install
                                        </Button>
                                    </div>
                                ))}
                            </div>
                        </>
                    )}
                </>
            )}
        </Dialog>
    );
};

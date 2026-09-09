import { faNetworkWired } from '@fortawesome/free-solid-svg-icons';
import type { FormikHelpers } from 'formik';
import { Form, Formik, useFormikContext } from 'formik';
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import tw from 'twin.macro';
import { object } from 'yup';

import type { Egg } from '@definitions/admin';
import type { CreateServerRequest } from '@/api/routes/admin/servers';
import { createServerEntry as createServer } from '@/api/routes/admin/servers';
import type { Node } from '@definitions/admin';
import AdminBox from '@/elements/AdminBox';
import NodeSelect from '@admin/management/servers/NodeSelect';
import {
    ServerImageContainer,
    ServerServiceContainer,
    ServerVariableContainer,
} from '@admin/management/servers/ServerStartupContainer';
import BaseSettingsBox from '@admin/management/servers/settings/BaseSettingsBox';
import FeatureLimitsBox from '@admin/management/servers/settings/FeatureLimitsBox';
import ServerResourceBox from '@admin/management/servers/settings/ServerResourceBox';
import ModpackPicker from '@admin/management/servers/modpack/ModpackPicker';
import { Button } from '@/elements/button';
import Field from '@/elements/Field';
import FormikSwitch from '@/elements/FormikSwitch';
import Label from '@/elements/Label';
import SpinnerOverlay from '@/elements/SpinnerOverlay';
import FlashMessageRender from '@/elements/FlashMessageRender';
import useFlash from '@/plugins/useFlash';
import AdminContentBlock from '@/elements/AdminContentBlock';
import { WithRelationships } from '@/api/routes/admin';
import { AsyncSelectField } from '@/elements/SelectField';
import type { Option } from '@/elements/SelectField';
import { getNodeAllocationEntries as getAllocations } from '@/api/routes/admin/nodes';
import { Alert } from '@/elements/alert';

function InternalForm() {
    const {
        isSubmitting,
        isValid,
        setFieldValue,
        values: { environment },
    } = useFormikContext<CreateServerRequest>();

    const [egg, setEgg] = useState<WithRelationships<Egg, 'variables'> | undefined>(undefined);
    const [node, setNode] = useState<Node | null>(null);
    const [pickerOpen, setPickerOpen] = useState(false);

    const handleModpackPick = (projectId: string, versionId: string, _name: string, provider: string = 'modrinth', mcVersion?: string, loader?: string) => {
        const env: Record<string, string> = {
            PROJECT_ID: projectId,
            VERSION_ID: versionId,
            PROVIDER: provider,
        };
        if (mcVersion && mcVersion !== 'unknown') env.MC_VERSION = mcVersion;
        if (loader && loader !== 'unknown') env.LOADER = loader;
        setFieldValue('environment', {
            ...environment,
            ...env,
        });
    };

    useEffect(() => {
        if (egg === undefined) {
            return;
        }

        setFieldValue('eggId', egg.id);
        setFieldValue('startup', '');
        setFieldValue('image', Object.values(egg.dockerImages)[0] ?? '');
    }, [egg]);

    // Auto-fill modpack IDs picked on the /browse page (stored in localStorage).
    useEffect(() => {
        const applyPick = () => {
            try {
                const raw = window.localStorage.getItem('modpack_pick');
                if (!raw) return;
                const pick = JSON.parse(raw) as { pid?: string; vid?: string; prov?: string; mc?: string; loader?: string };
                if (!pick.pid) return;
                if (egg?.id !== 15) return;
                const env: Record<string, string> = {
                    PROJECT_ID: pick.pid,
                    VERSION_ID: pick.vid || 'latest',
                    PROVIDER: pick.prov || 'modrinth',
                };
                if (pick.mc && pick.mc !== 'unknown') env.MC_VERSION = pick.mc;
                if (pick.loader && pick.loader !== 'unknown') env.LOADER = pick.loader;
                if (pick.prov === 'manual') {
                    env.MODPACK_ZIP = pick.pid;
                }
                setFieldValue('environment', { ...environment, ...env });
                window.localStorage.removeItem('modpack_pick');
            } catch {
                /* ignore bad stored value */
            }
        };
        applyPick();
        window.addEventListener('focus', applyPick);
        return () => window.removeEventListener('focus', applyPick);
    }, [egg]);

    const loadOptions = async (inputValue: string, callback: (options: Option[]) => void) => {
        if (!node) {
            callback([] as Option[]);
            return;
        }

        const allocations = await getAllocations(node.id, { search: inputValue, server_id: '0' });

        callback(
            allocations.map(a => {
                return { value: a.id.toString(), label: a.getDisplayText() };
            }),
        );
    };

    return (
        <Form>
            <div className="grid grid-cols-2 gap-y-6 gap-x-8 mb-16">
                <div className="grid grid-cols-1 gap-y-6 col-span-2 md:col-span-1">
                    <BaseSettingsBox>
                        <NodeSelect node={node} setNode={setNode} />
                        <div className="xl:col-span-2 bg-neutral-800 border border-neutral-900 shadow-inner p-4 rounded">
                            <FormikSwitch
                                name={'startOnCompletion'}
                                label={'Start after installation'}
                                description={'Should the server be automatically started after it has been installed?'}
                            />
                        </div>
                    </BaseSettingsBox>
                    <FeatureLimitsBox />
                    <ServerServiceContainer selectedEggId={egg?.id} setEgg={setEgg} nestId={0} />
                </div>
                <div className="grid grid-cols-1 gap-y-6 col-span-2 md:col-span-1">
                    <AdminBox icon={faNetworkWired} title="Networking" isLoading={isSubmitting}>
                        <div className="grid grid-cols-1 gap-4 lg:gap-6">
                            <div>
                                <Label htmlFor={'allocation.default'}>Primary Allocation</Label>
                                {!node ? (
                                    <Alert type={'info'}>Select a node to view allocations.</Alert>
                                ) : (
                                    <AsyncSelectField
                                        id={'allocation.default'}
                                        name={'allocation.default'}
                                        loadOptions={loadOptions}
                                        defaultOptions
                                        menuPortalTarget={document.body}
                                        menuPosition="fixed"
                                        maxMenuHeight={320}
                                    />
                                )}
                            </div>
                        </div>
                    </AdminBox>
                    <ServerResourceBox />
                    <ServerImageContainer />
                </div>

                <AdminBox title={'Startup Command'} className="relative w-full col-span-2">
                    <SpinnerOverlay visible={isSubmitting} />

                    <Field
                        id={'startup'}
                        name={'startup'}
                        label={'Startup Command'}
                        type={'text'}
                        description={
                            "Edit your server's startup command here. The following variables are available by default: {{SERVER_MEMORY}}, {{SERVER_IP}}, and {{SERVER_PORT}}."
                        }
                        placeholder={egg?.startup || ''}
                    />
                </AdminBox>

                <div className="col-span-2 grid grid-cols-1 md:grid-cols-2 gap-y-6 gap-x-8">
                    {/* Modpack browser - opens the standalone /browse page in a new tab */}
                    {egg?.id === 15 && (
                        <div className="col-span-2 bg-blue-900/30 border border-blue-500 rounded p-4 flex items-center justify-between">
                            <div>
                                <p className="text-white font-semibold">Install a modpack</p>
                                <p className="text-sm text-neutral-300">Pick a modpack and version — the IDs fill in automatically below.</p>
                            </div>
                            <Button type="button" onClick={() => setPickerOpen(true)}>
                                Browse Modpacks
                            </Button>
                            <a href="/browse" target="_blank" rel="noreferrer" className="ml-3 text-sm text-blue-400 hover:underline">
                                full page
                            </a>
                        </div>
                    )}

                    {/* This ensures that no variables are rendered unless the environment has a value for the variable. */}
                    {egg?.relationships.variables
                        ?.filter(v => Object.keys(environment).find(e => e === v.environmentVariable) !== undefined)
                        .map((v, i) => (
                            <ServerVariableContainer key={i} variable={v} />
                        ))}
                </div>

                <div className="bg-neutral-700 rounded shadow-md px-4 py-3 col-span-2">
                    <div className="flex flex-row">
                        <Button type="submit" className="ml-auto" disabled={isSubmitting || !isValid}>
                            Create Server
                        </Button>
                    </div>
                </div>
            </div>
            <ModpackPicker
                open={pickerOpen}
                onClose={() => setPickerOpen(false)}
                onSelect={handleModpackPick}
            />
        </Form>
    );
}

export default () => {
    const navigate = useNavigate();

    const { clearFlashes, clearAndAddHttpError } = useFlash();

    const submit = (r: CreateServerRequest, { setSubmitting }: FormikHelpers<CreateServerRequest>) => {
        clearFlashes('server:create');

        createServer(r)
            .then(s => navigate(`/admin/servers/${s.id}`))
            .catch(error => clearAndAddHttpError({ key: 'server:create', error }))
            .then(() => setSubmitting(false));
    };

    return (
        <AdminContentBlock title={'New Server'}>
            <div css={tw`w-full flex flex-row items-center mb-8`}>
                <div css={tw`flex flex-col flex-shrink`} style={{ minWidth: '0' }}>
                    <h2 css={tw`text-2xl text-neutral-50 font-header font-medium`}>New Server</h2>
                    <p
                        css={tw`hidden md:block text-base text-neutral-400 whitespace-nowrap overflow-ellipsis overflow-hidden`}
                    >
                        Add a new server to the panel.
                    </p>
                </div>
            </div>

            <FlashMessageRender byKey={'server:create'} css={tw`mb-4`} />

            <Formik
                onSubmit={submit}
                initialValues={
                    {
                        externalId: '',
                        name: '',
                        description: '',
                        ownerId: 0,
                        nodeId: 0,
                        limits: {
                            memory: 1024,
                            swap: 0,
                            disk: 4096,
                            io: 500,
                            cpu: 0,
                            threads: '',
                            oomKiller: true,
                        },
                        featureLimits: {
                            allocations: 1,
                            backups: 0,
                            databases: 0,
                            subusers: 0,
                        },
                        allocation: {
                            default: 0,
                            additional: [] as number[],
                        },
                        startup: '',
                        environment: [],
                        eggId: 0,
                        image: '',
                        skipScripts: false,
                        startOnCompletion: true,
                    } as CreateServerRequest
                }
                validationSchema={object().shape({})}
            >
                <InternalForm />
            </Formik>
        </AdminContentBlock>
    );
};

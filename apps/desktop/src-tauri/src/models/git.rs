use serde::Serialize;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GitCapabilities {
    pub git_installed: bool,
    pub git_version: Option<String>,
    pub supports_partial_clone: bool,
    pub supports_sparse_checkout: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthStatus {
    pub ssh_agent_available: bool,
    pub credential_helper_configured: bool,
    pub diagnostics: Vec<String>,
    pub remote_diagnostics: Vec<RemoteAuthDiagnostic>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteAuthDiagnostic {
    pub remote: String,
    pub url: String,
    pub protocol: String,
    pub guidance: String,
}

#[derive(Debug, Serialize)]
pub struct ForgeAdapter {
    pub id: String,
    pub available: bool,
    pub version: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ForgeAdapterList {
    pub adapters: Vec<ForgeAdapter>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteIntegrationData {
    pub remote: String,
    pub url: String,
    pub host_kind: String,
    pub adapter_id: Option<String>,
    pub adapter_available: bool,
    pub offline_supported: bool,
    pub capability_summary: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryIntegrationMatrix {
    pub repository_path: String,
    pub offline_ready: bool,
    pub local_features: Vec<String>,
    pub remotes: Vec<RemoteIntegrationData>,
}

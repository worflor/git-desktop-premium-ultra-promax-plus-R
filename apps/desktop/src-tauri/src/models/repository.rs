use serde::Serialize;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenRepositoryData {
    pub repository_path: String,
    pub is_valid_git_repository: bool,
}

#[derive(Debug, Serialize)]
pub struct RecentRepositoriesData {
    pub repositories: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct RepositoryStatusFile {
    pub path: String,
    pub staged: String,
    pub unstaged: String,
}

#[derive(Debug, Serialize)]
pub struct RepositoryStatusData {
    pub branch: String,
    pub ahead: u32,
    pub behind: u32,
    pub files: Vec<RepositoryStatusFile>,
}

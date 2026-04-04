use std::collections::HashMap;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiReviewJobState {
    Queued,
    Running,
    Completed,
    Failed,
    Canceled,
}

impl AiReviewJobState {
    pub fn as_str(&self) -> &'static str {
        match self {
            AiReviewJobState::Queued => "queued",
            AiReviewJobState::Running => "running",
            AiReviewJobState::Completed => "completed",
            AiReviewJobState::Failed => "failed",
            AiReviewJobState::Canceled => "canceled",
        }
    }

    pub fn is_terminal(&self) -> bool {
        matches!(
            self,
            AiReviewJobState::Completed | AiReviewJobState::Failed | AiReviewJobState::Canceled
        )
    }
}

pub struct AiReviewJobRecord {
    pub status: AiReviewJobState,
    pub output: String,
    pub error: Option<String>,
    pub cancel_flag: Arc<AtomicBool>,
    pub provider_id: String,
    pub repository_path: String,
    pub diff_scope_path: Option<String>,
    pub prompt: String,
}

pub type SharedAiReviewJob = Arc<Mutex<AiReviewJobRecord>>;

pub struct AppState {
    pub recent_repositories: Mutex<Vec<String>>,
    pub ai_review_jobs: Mutex<HashMap<String, SharedAiReviewJob>>,
    pub contract_version: String,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            recent_repositories: Mutex::new(Vec::new()),
            ai_review_jobs: Mutex::new(HashMap::new()),
            contract_version: "v0".to_string(),
        }
    }
}

use serde::Serialize;

#[derive(Debug, Serialize)]
#[serde(untagged)]
pub enum CommandResult<T>
where
    T: Serialize,
{
    Ok {
        ok: bool,
        data: T,
        meta: Option<ResponseMeta>,
    },
    Err {
        ok: bool,
        error: CommandError,
        meta: Option<ResponseMeta>,
    },
}

impl<T> CommandResult<T>
where
    T: Serialize,
{
    pub fn ok(data: T, meta: ResponseMeta) -> Self {
        Self::Ok {
            ok: true,
            data,
            meta: Some(meta),
        }
    }

    pub fn error(error: CommandError, meta: ResponseMeta) -> Self {
        Self::Err {
            ok: false,
            error,
            meta: Some(meta),
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResponseMeta {
    pub request_id: String,
    pub duration_ms: u64,
    pub version: String,
}

#[derive(Debug, Serialize)]
pub struct CommandError {
    pub code: String,
    pub message: String,
    pub details: Option<std::collections::HashMap<String, serde_json::Value>>,
    pub retryable: bool,
}

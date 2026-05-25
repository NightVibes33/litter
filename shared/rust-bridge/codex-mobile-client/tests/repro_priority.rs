use codex_app_server_protocol as upstream;
use serde_json::json;

#[test]
fn priority_deserializes() {
    let payload = json!({
        "thread": {
            "id": "thread-1",
            "sessionId": "session-1",
            "preview": "hi",
            "ephemeral": false,
            "modelProvider": "openai",
            "createdAt": 1,
            "updatedAt": 2,
            "status": { "type": "idle" },
            "path": "/tmp/thread",
            "cwd": "/tmp/thread",
            "cliVersion": "1.0.0",
            "source": "cli",
            "serviceTier": "priority",
            "agentNickname": null,
            "agentRole": null,
            "gitInfo": null,
            "name": "thread",
            "turns": []
        },
        "model": "gpt-5",
        "modelProvider": "openai",
        "serviceTier": "priority",
        "cwd": "/tmp/thread",
        "approvalPolicy": "on-request",
        "approvalsReviewer": "user",
        "sandbox": { "type": "readOnly" },
        "reasoningEffort": "medium"
    });

    match serde_json::from_value::<upstream::ThreadResumeResponse>(payload) {
        Ok(r) => println!("OK: service_tier = {:?}", r.service_tier),
        Err(e) => panic!("ERR: {}", e),
    }
}

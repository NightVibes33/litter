import { sendSilentPush } from "./apns"
import { ContentState, Env, RegisterRequest } from "./types"

interface StoredRegistration {
  platform: "ios"
  pushToken: string
  apnsEnvironment: "production" | "sandbox"
  intervalSeconds: number
  ttlSeconds: number
  pushCount: number
  createdAt: number // ms
  contentState?: ContentState
}

export class PushRegistration implements DurableObject {
  private state: DurableObjectState
  private env: Env

  constructor(state: DurableObjectState, env: Env) {
    this.state = state
    this.env = env
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url)

    if (request.method === "PUT" && url.pathname === "/") {
      const body = (await request.json()) as RegisterRequest
      if (body.platform !== "ios") {
        return new Response("unsupported platform", { status: 400 })
      }
      if (typeof body.pushToken !== "string" || body.pushToken.trim().length === 0) {
        return new Response("missing pushToken", { status: 400 })
      }
      const apnsEnvironment = body.apnsEnvironment ?? "production"
      if (apnsEnvironment !== "production" && apnsEnvironment !== "sandbox") {
        return new Response("invalid APNs environment", { status: 400 })
      }
      const intervalSeconds = typeof body.intervalSeconds === "number" && Number.isFinite(body.intervalSeconds) && body.intervalSeconds > 0
        ? body.intervalSeconds
        : 30
      const ttlSeconds = typeof body.ttlSeconds === "number" && Number.isFinite(body.ttlSeconds) && body.ttlSeconds > 0
        ? body.ttlSeconds
        : 7200
      const reg: StoredRegistration = {
        platform: "ios",
        pushToken: body.pushToken.trim(),
        apnsEnvironment,
        intervalSeconds,
        ttlSeconds,
        pushCount: 0,
        createdAt: Date.now(),
        contentState: body.contentState,
      }
      await this.state.storage.put("reg", reg)
      await this.state.storage.setAlarm(Date.now() + reg.intervalSeconds * 1000)
      return new Response("ok")
    }

    if (request.method === "POST" && url.pathname === "/deregister") {
      await this.state.storage.deleteAll()
      return new Response("ok")
    }

    return new Response("not found", { status: 404 })
  }

  async alarm(): Promise<void> {
    const reg = await this.state.storage.get<StoredRegistration>("reg")
    if (!reg) return

    const now = Date.now()
    if (reg.createdAt + reg.ttlSeconds * 1000 < now) {
      console.log(`TTL expired after ${reg.pushCount} pushes`)
      await this.state.storage.deleteAll()
      return
    }

    reg.pushCount++

    const result = await sendSilentPush(this.env, reg.pushToken, reg.apnsEnvironment)
    if (result.gone) {
      await this.state.storage.deleteAll()
      return
    }

    await this.state.storage.put("reg", reg)
    await this.state.storage.setAlarm(now + reg.intervalSeconds * 1000)
  }
}

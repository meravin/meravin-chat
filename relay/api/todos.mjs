// Today's To Do, including the long-press "设为日程" action, which is just a
// due date being written onto an existing item.
import { randomUUID } from 'node:crypto'
import { badRequest, notFound, readJson, sendJson } from './http.mjs'

const OWNERS = new Set(['user', 'ai_a', 'ai_b'])
const STATES = new Set(['pending', 'done'])

const requireOwner = (value) => {
  const owner = value ?? 'user'
  if (!OWNERS.has(owner)) throw badRequest('bad_owner', `unknown owner: ${owner}`)
  return owner
}

export function todoRoutes({ store }) {
  return {
    'GET /api/todos': async (req, res, { query }) => {
      const owner = requireOwner(query.get('owner'))
      const limit = Math.min(Number(query.get('limit')) || 100, 500)
      let items = store.listTodos(owner, limit)
      const state = query.get('state')
      if (state) {
        if (!STATES.has(state)) throw badRequest('bad_state', `unknown state: ${state}`)
        items = items.filter((t) => t.state === state)
      }
      return sendJson(res, 200, { owner, items })
    },

    'POST /api/todos': async (req, res) => {
      const body = await readJson(req)
      const owner = requireOwner(body.owner)
      const title = typeof body.title === 'string' ? body.title.trim() : ''
      if (!title) throw badRequest('empty_title', 'title is required')

      const item = store.createTodo({
        id: body.id ?? randomUUID(),
        owner,
        title,
        // e.g. "23:49 添加" for a quick add, or "7月25日记的" when lifted out of a diary entry
        source: body.source ?? null,
        dueAt: body.dueAt ?? null,
      })
      return sendJson(res, 201, { item })
    },

    'PATCH /api/todos/:id': async (req, res, { params }) => {
      if (!store.getTodo(params.id)) throw notFound('no such todo')
      const body = await readJson(req)
      if (body.state !== undefined && !STATES.has(body.state)) {
        throw badRequest('bad_state', `unknown state: ${body.state}`)
      }
      const item = store.updateTodo(params.id, {
        title: typeof body.title === 'string' ? body.title.trim() : undefined,
        state: body.state,
        // Present-but-null clears the schedule; absent leaves it alone.
        dueAt: 'dueAt' in body ? body.dueAt : undefined,
      })
      return sendJson(res, 200, { item })
    },

    'DELETE /api/todos/:id': async (req, res, { params }) => {
      if (!store.deleteTodo(params.id)) throw notFound('no such todo')
      return sendJson(res, 200, { deleted: params.id })
    },
  }
}

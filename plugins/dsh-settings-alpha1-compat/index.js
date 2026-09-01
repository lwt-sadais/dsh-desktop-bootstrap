export const name = 'settings-alpha1-compat'
export const inject = ['settings']

const FIBER_DISPOSED = 4
const FIBER_UNLOADING = 5

/**
 * 判断插件拥有者是否正在卸载，避免在销毁期间重新注册资源。
 *
 * @param {import('@deepseek-ai/cordis').Context} owner 设置域拥有者上下文。
 * @returns {boolean} 是否已进入卸载或销毁状态。
 */
function isUnloading(owner) {
  return owner.fiber.state === FIBER_UNLOADING || owner.fiber.state === FIBER_DISPOSED
}

/**
 * 为 Harness alpha.1 的设置服务补齐 alpha.2 引入的实例方法。
 * 新版 Host 已原生实现该方法时保持原实现，不执行覆盖。
 *
 * @param {import('@deepseek-ai/cordis').Context} ctx 当前插件上下文。
 */
export function apply(ctx) {
  const settings = ctx.settings
  if (typeof settings.installSection === 'function') return

  Object.defineProperty(settings, 'installSection', {
    configurable: true,
    value(owner, namespace, schema, entry, hooks) {
      const scope = this.register(namespace, schema, {
        base: entry,
        ...(hooks.validate === undefined ? {} : { validate: hooks.validate }),
      })
      hooks.setSource(() => scope.get())
      this.ctx.effect(() => () => {
        if (isUnloading(owner)) return
        hooks.setSource(() => entry)
        hooks.onChange()
      }, `settings compatibility section: ${String(namespace)}`)
      hooks.onChange()
      scope.watch(() => {
        if (isUnloading(owner)) return
        hooks.onChange()
      })
    },
  })

  ctx.effect(() => () => {
    delete settings.installSection
  }, 'settings alpha.1 compatibility method')
}

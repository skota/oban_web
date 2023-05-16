import "phoenix_html"
import {Socket, LongPoll} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import tippy, {roundArrow} from "tippy.js"
import topbar from "topbar"

// Topbar ---

let topBarScheduled = undefined

topbar.config({barColors: {0: "#0284c7"}, shadowColor: "rgba(0, 0, 0, .3)"})

window.addEventListener("phx:page-loading-start", (info) => {
  if(!topBarScheduled) {
    topBarScheduled = setTimeout(() => topbar.show(), 500)
  }
})

window.addEventListener("phx:page-loading-stop", (info) => {
  clearTimeout(topBarScheduled)
  topBarScheduled = undefined
  topbar.hide()
})

// Hooks ---

let Hooks = {}

Hooks.Refresher = {
  mounted() {
    const targ = "#refresh-selector"
    const elem = this

    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") {
        elem.pushEventTo(targ, "resume-refresh", {})
      } else {
        elem.pushEventTo(targ, "pause-refresh", {})
      }
    })

    if ("refresh" in localStorage) {
      elem.pushEventTo(targ, "select-refresh", {value: localStorage.refresh})
    }

    this.el.querySelectorAll("[role='option']").forEach(option => {
      option.addEventListener("click", () => {
        localStorage.refresh = option.getAttribute("value")
      })
    });
  }
}

Hooks.RestoreTheme = {
  mounted() {
    this.pushEventTo("#theme-selector", "restore", {theme: localStorage.theme})
  }
}

Hooks.ChangeTheme = {
  applyTheme() {
    const wantsDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    const noPreference = !("theme" in localStorage)

    if ((localStorage.theme === "dark") || (localStorage.theme === "system" && wantsDark) || (noPreference && wantsDark)) {
      document.documentElement.classList.add("dark")
    } else {
      document.documentElement.classList.remove("dark")
    }
  },

  mounted() {
    let elem = this;

    this.el.addEventListener("click", () => {
      const theme = this.el.getAttribute("value")

      localStorage.theme = theme

      this.applyTheme()

      elem.pushEventTo("#theme-selector", "restore", {theme: theme})
    })
  }
}

Hooks.Tippy = {
  mounted() {
    const content = this.el.getAttribute("data-title");

    tippy(this.el, { arrow: roundArrow, content: content, delay: [250, null] });
  }
}

Hooks.Chart = {
  mounted() {
    const toolY = 192
    const toolXOffset = 32
    const textHeight = 16
    const textPadding = 2
    const baseLabelX = 12
    const baseLabelY = 42
    const timeOpts = { hour12: false, timeStyle: "long" }

    const tooltip = this.el.querySelector("#chart-tooltip")
    const datacol = this.el.querySelector("#chart-d")
    const tooltxt = tooltip.querySelector("[rel='date']")
    const toolrct = tooltip.querySelector("[rel='rect']")
    const tlabels = [...tooltip.querySelectorAll("g")]

    datacol.addEventListener("mouseenter", () => {
      tooltip.setAttribute("display", "visible")
    })

    datacol.addEventListener("mouseleave", () => {
      tooltip.setAttribute("display", "none")
    })

    datacol.addEventListener("mouseover", event => {
      const parent = event.target.parentElement
      const offset = parent.getAttribute("data-offset") - toolXOffset
      const trects = parent.querySelectorAll("rect[data-value]")
      const tstamp = parent.getAttribute("data-tstamp") * 1000
      const tevent = new Date(tstamp)

      tooltip.setAttribute("transform", `translate(${offset},${toolY})`)
      tooltxt.childNodes[0].nodeValue = tevent.toLocaleTimeString("en-US", timeOpts)

      tlabels.forEach(el => el.setAttribute("display", "none"));

      let y = baseLabelY

      trects.forEach(el => {
        const label = el.getAttribute("data-label")
        const value = el.getAttribute("data-value")
        const group = tlabels.find(tlab => tlab.getAttribute("rel") === label)
        const gtext = group.querySelector("text").childNodes[0]

        gtext.nodeValue = `${label} ${value}`
        group.setAttribute("display", "visible")
        group.setAttribute("transform", `translate(${baseLabelX}, ${y})`)

        y += textHeight;
      })

      toolrct.setAttribute("height", y - textHeight + textPadding);
    })
  }
}

// Mounting ---

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const liveTran = document.querySelector("meta[name='live-transport']").getAttribute("content");
const livePath = document.querySelector("meta[name='live-path']").getAttribute("content");

const liveSocket = new LiveSocket(livePath, Socket, {
  transport: liveTran === "longpoll" ? LongPoll : WebSocket,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
});

liveSocket.connect();

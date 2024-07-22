document.write(`
<style>
    body {
        /* background-color: red; */
    }

    #app_splash {
        padding: 32px;
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        opacity: 0;
        transition: opacity 300ms cubic-bezier(0, 0, 0.2, 1);
        will-change: opacity;
        z-index: 100;
        background: black url("assets/packages/tekaly_assets/img/tekartik_logo_256.png") no-repeat center;
        background-size: 256px 256px;
        background-origin: content-box;
    }

    #app_splash.app-loading {
        opacity: 1;
    }

    @media screen and (max-width: 384px) {
        #app_splash {
            background-size: contain;
        }
    }
</style>
<div id="app_splash" class="app-loading"></div>
`);
PORTNAME=	doumi
DISTVERSION=	0.1.0
CATEGORIES=	sysutils

MAINTAINER=	doumi@example.com
COMMENT=	Intelligent file organizer with real-time watching and cron scheduling
WWW=		https://github.com/xirtus/doumi

LICENSE=	MIT
LICENSE_FILE=	${WRKSRC}/LICENSE

USES=		cargo desktop-file-utils gnome pkgconfig
USE_GITHUB=	yes
GH_ACCOUNT=	xirtus

USE_GNOME=	gtk40 libadwaita

CARGO_BUILD=	yes
CARGO_INSTALL=	yes
CARGO_TEST=	yes
CARGO_CARGOLOCK=	${WRKSRC}/Cargo.lock

PLIST_FILES=	bin/doumi \
		bin/doumid \
		bin/doumi-gui \
		share/applications/doumi.desktop \
		share/icons/hicolor/16x16/apps/doumi.png \
		share/icons/hicolor/32x32/apps/doumi.png \
		share/icons/hicolor/48x48/apps/doumi.png \
		share/icons/hicolor/64x64/apps/doumi.png \
		share/icons/hicolor/128x128/apps/doumi.png \
		share/icons/hicolor/256x256/apps/doumi.png \
		share/icons/hicolor/512x512/apps/doumi.png \
		share/icons/hicolor/scalable/apps/doumi.svg

USE_RC_SUBR=	doumid

post-install:
	@${MKDIR} ${STAGEDIR}${PREFIX}/share/applications
	${INSTALL_DATA} ${WRKSRC}/packaging/freebsd/doumi.desktop \
		${STAGEDIR}${PREFIX}/share/applications/doumi.desktop
.for sz in 16 32 48 64 128 256 512
	@${MKDIR} ${STAGEDIR}${PREFIX}/share/icons/hicolor/${sz}x${sz}/apps
	${INSTALL_DATA} ${WRKSRC}/data/icons/doumi_${sz}.png \
		${STAGEDIR}${PREFIX}/share/icons/hicolor/${sz}x${sz}/apps/doumi.png
.endfor
	@${MKDIR} ${STAGEDIR}${PREFIX}/share/icons/hicolor/scalable/apps
	${INSTALL_DATA} ${WRKSRC}/data/icons/doumi.svg \
		${STAGEDIR}${PREFIX}/share/icons/hicolor/scalable/apps/doumi.svg

.include <bsd.port.mk>

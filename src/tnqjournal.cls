\NeedsTeXFormat{LaTeX2e}[2023-11-01]
\ProvidesClass{tnqjournal}[2026/07/14 v0.4 measured URP transactional first-page builder]
\LoadClass[10pt,twocolumn,twoside]{article}
\RequirePackage{iftex}
\ifLuaTeX\else\ClassError{tnqjournal}{LuaLaTeX is required}{}\fi
\IfDocumentMetadataTF{%
  \ClassError{tnqjournal}{Tagged PDF/DocumentMetadata requires a separate transaction protocol}%
    {The prose transaction does not own structure trees or MCID allocation.}%
}{}
\RequirePackage{fontspec}
\setmainfont{Carlito}
\setsansfont{Roboto Condensed}
\newfontfamily\tnqsymbolfont{Noto Sans Symbols2}
\newfontfamily\tnqmetafont{Noto Sans}
\RequirePackage{xcolor}
\RequirePackage{graphicx}
\RequirePackage{ragged2e}
\RequirePackage{eso-pic}
\RequirePackage{geometry}
\RequirePackage{microtype}
\RequirePackage{titlesec}
\RequirePackage{fancyhdr}
\RequirePackage{enumitem}
\RequirePackage{caption}
\RequirePackage{dblfloatfix}

\definecolor{tnqblue}{HTML}{263373}
\definecolor{tnqlight}{HTML}{E9EBF1}
\definecolor{tnqgreen}{HTML}{92CD1D}
\definecolor{tnqgray}{HTML}{55585E}
\definecolor{tnqcyan}{HTML}{10A8E0}
\definecolor{tnqtext}{HTML}{2C2E35}
\geometry{paperwidth=609.12bp,paperheight=793.92bp,
  top=46pt,bottom=35pt,left=46pt,right=43pt,
  headheight=10pt,headsep=15pt,footskip=25pt}
\setlength\columnsep{18pt}
\setlength\parindent{0pt}
\setlength\parskip{4.1pt plus .6pt minus .4pt}
\setlength\emergencystretch{1.2em}
\setlist{nosep,leftmargin=12pt}
\captionsetup{font=small,labelfont=bf}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[LE]{\bfseries\fontsize{7.2}{8}\selectfont\@articlemeta}
\fancyhead[RO]{\bfseries\fontsize{7.2}{8}\selectfont\@shorttitle}
\renewcommand\headrulewidth{0pt}
\renewcommand\footrulewidth{0pt}
\fancypagestyle{tnqfirst}{%
  \fancyhf{}%
  \renewcommand\headrulewidth{0pt}%
  \renewcommand\footrulewidth{0pt}}

\newcommand\journalname[1]{\gdef\@journalname{#1}}
\newcommand\journalwordmark[1]{\gdef\@journalwordmark{#1}}
\newcommand\journalsubtitle[1]{\gdef\@journalsubtitle{#1}}
\newcommand\articlemeta[1]{\gdef\@articlemeta{#1}}
\newcommand\articletype[1]{\gdef\@articletype{#1}}
\newcommand\journalsection[1]{\gdef\@journalsection{#1}}
\newcommand\doi[1]{\gdef\@doi{#1}}
\newcommand\shorttitle[1]{\gdef\@shorttitle{#1}}
\newcommand\journallogo[1]{\gdef\@journallogo{#1}}
\newcommand\licensebadge[1]{\gdef\@licensebadge{#1}}
\newcommand\firstpagefooter[1]{\gdef\@firstpagefooter{#1}}
\newcommand\abstracttext[1]{\gdef\@abstracttext{#1}}
\newcommand\keywords[1]{\gdef\@keywords{#1}}
\newcommand\authorstub[1]{\gdef\@authorstub{#1}}
\newcommand\stubdetails[1]{{\sffamily\fontsize{6.8}{8.4}\selectfont
  \baselineskip8.4pt\lineskiplimit-1000pt\parskip0pt #1}}
\newcommand\stubcitation[1]{\par\begingroup
  \sffamily\fontsize{6.8}{8.4}\selectfont
  \baselineskip8.4pt\lineskiplimit-1000pt\parskip0pt #1\par\endgroup}
\newcommand\orcidmark{\raisebox{.15ex}{%
  \includegraphics[width=8.64bp]{assets/orcid-id.png}}}
\journalname{Urology Research and Practice}
\journalwordmark{UROLOGY}
\journalsubtitle{RESEARCH \& PRACTICE}
\articlemeta{Urology Research and Practice 2026;52:1--7}
\articletype{ORIGINAL ARTICLE}
\journalsection{Endourology}
\doi{10.5152/tud.2026.00000}
\shorttitle{Author et al. Short title}
\IfFileExists{assets/urp-journal-logo.png}{%
  \journallogo{assets/urp-journal-logo.png}}{\journallogo{}}
\IfFileExists{assets/urp-cc-by.png}{%
  \licensebadge{assets/urp-cc-by.png}}{\licensebadge{}}
\firstpagefooter{}
\abstracttext{}\keywords{}\authorstub{}

\titleformat{\section}{\sffamily\bfseries\color{tnqblue}\fontsize{12.2}{13.5}\selectfont}{}{0pt}{}
\titlespacing*{\section}{0pt}{7pt}{2.5pt}
\titleformat{\subsection}{\sffamily\bfseries\color{tnqblue}\fontsize{9.8}{11}\selectfont}{}{0pt}{}
\titlespacing*{\subsection}{0pt}{5pt}{1pt}

\directlua{tnqjournal = dofile(kpse.find_file('tnqjournal.lua'))}
% Record the last fully formed line immediately before every LaTeX mark-class
% insertion.  The internal anchor is removed from transaction-owned copies;
% it lets Lua restore semantic mark ownership when TeX has exposed a mark
% ahead of lines retained by the special first-page split.
\AddToHook{insertmark}{\directlua{tnqjournal.write_mark_anchor()}}

\newcount\tnq@validate
\edef\tnq@validate@number{\the\allocationnumber}
\newcount\tnq@widthadjust
\edef\tnq@widthadjust@number{\the\allocationnumber}
\directlua{tnqjournal.setup{
  validate=\tnq@validate@number,width_adjust=\tnq@widthadjust@number}}

\newbox\tnq@header
\newbox\tnq@stub
\newbox\tnq@mainwork
\newbox\tnq@mainpage
\newbox\tnq@stubwork
\newbox\tnq@stubpage
\newbox\tnq@stubstage
\newbox\tnq@stubtailstage
\newdimen\tnq@available
\newdimen\tnq@stubreserve
\newdimen\tnq@stubmax
\newdimen\tnq@firstmainwidth
\newdimen\tnq@firstleftindent
\newdimen\tnq@firstgutter
\newdimen\tnq@stubwidth
\newdimen\tnq@stuboffset
\newdimen\tnq@footerreserve
\newdimen\tnq@nativeshift
\newcount\tnq@state
\newcount\tnq@savedoutputpenalty
\newcount\tnq@draincycles
\newcount\tnq@widelines
\newcount\tnq@shapeloop
\newdimen\tnq@remaining
\newdimen\tnq@mainsplittarget
\newcount\tnq@splitretries
\newif\iftnq@stubstage
\newif\iftnq@transitionpending
\newif\iftnq@transactionarmed
\newtoks\tnq@nativeoutput
\def\tnq@wrappednativeoutput{%
  \directlua{tnqjournal.suspend_decoration(true)}%
  \the\tnq@nativeoutput
  \directlua{tnqjournal.suspend_decoration(false)}%
}

% 0 unarmed, 1 first page building, 2 native/stub continuation.
\global\tnq@state\z@
\global\tnq@stubstagefalse
\global\tnq@transitionpendingfalse
\global\tnq@transactionarmedfalse
\tnq@firstmainwidth=344pt
\tnq@firstleftindent=24pt
\tnq@firstgutter=23pt
\tnq@stubwidth=\dimexpr\textwidth-\tnq@firstleftindent-
  \tnq@firstmainwidth-\tnq@firstgutter\relax
\tnq@stuboffset=159.7pt
\tnq@footerreserve=45pt
\tnq@nativeshift=19.3pt

% The reference page has a 344pt main measure, while native page-2 columns are
% about 249pt.  Before each page-1 paragraph is broken, form only the number of
% lines that can still fit in the special lane at 344pt; the final parshape
% entry repeats at native \columnwidth.  If the paragraph crosses the page,
% TeX has therefore already formed its remainder at the correct native width.
% The page builder still selects the actual breakpoint and the transaction
% still moves complete, already formed line boxes.
\def\tnq@shape@firstpage{%
  \ifnum\tnq@state=\@ne
    \tnq@remaining\dimexpr\tnq@available-\pagetotal\relax
    \ifdim\tnq@remaining>\z@
      \tnq@widelines\tnq@remaining
      \@tempcnta\baselineskip
      \ifnum\@tempcnta>\z@
        \divide\tnq@widelines by\@tempcnta
      \else
        \tnq@widelines\z@
      \fi
    \else
      \tnq@widelines\z@
    \fi
    \ifnum\tnq@widelines<4
      % Do not start a fresh paragraph in the narrow transition zone.  Its
      % lines are formed at native width and a forced pre-line breakpoint lets
      % the page builder hand the complete paragraph to page 2.
      \parshape\@ne 0pt \columnwidth
      \global\tnq@transitionpendingtrue
      \vadjust pre{\penalty-\@M}%
    \else
      \edef\tnq@shape@spec{\the\numexpr\tnq@widelines+\@ne\relax}%
      \tnq@shapeloop\z@
      \loop\ifnum\tnq@shapeloop<\tnq@widelines
        \edef\tnq@shape@spec{\tnq@shape@spec\space
          0pt \the\tnq@firstmainwidth}%
        \advance\tnq@shapeloop\@ne
      \repeat
      \edef\tnq@shape@spec{\tnq@shape@spec\space
        0pt \the\columnwidth}%
      \expandafter\parshape\tnq@shape@spec\relax
    \fi
  \fi
}
\AddToHook{para/begin}{\tnq@shape@firstpage}
\def\tnq@reject@firstpage@footnote{%
  \iftnq@transactionarmed
    \ClassError{tnqjournal}{Footnotes require a separate first-page ownership protocol}%
      {Move the footnote after the page-1 handoff or disable the transactional profile.}%
  \fi
}
\AddToHook{cmd/footnote/before}{\tnq@reject@firstpage@footnote}
\AddToHook{cmd/footnotemark/before}{\tnq@reject@firstpage@footnote}
\AddToHook{cmd/footnotetext/before}{\tnq@reject@firstpage@footnote}
\AtBeginDocument{\color{tnqtext}\fontsize{8.55}{10.35}\selectfont\justifying}

\newcommand\tnq@rules{%
  % The reference footer stacks the page number over a short rule at fixed
  % trim-box coordinates; it is not an inline fancyhdr number/rule pair.
  \ifodd\value{page}
    \AtPageLowerLeft{\put(550,14.5){\makebox(0,0)[lb]{%
      \vbox{\hbox to17pt{\hfil\raisebox{-8.2pt}[0pt][0pt]{%
          \fontsize{8.55}{9}\selectfont\thepage}\kern-1pt}%
        \vskip1.5pt\textcolor{tnqblue}{\hrule height3.6pt width17pt}}}}}%
  \else
    \AtPageLowerLeft{\put(42.7,14.5){\makebox(0,0)[lb]{%
      \vbox{\hbox to17pt{\raisebox{-8.2pt}[0pt][0pt]{%
          \fontsize{8.55}{9}\selectfont\thepage}\hfil}%
        \vskip1.5pt\textcolor{tnqblue}{\hrule height3.6pt width17pt}}}}}%
  \fi
  \ifnum\value{page}=1\relax
    \AtPageLowerLeft{\color{tnqblue}\put(45.6,0){\rule{1.9pt}{673pt}}\put(45.6,704){\rule{1.9pt}{90pt}}}%
    \ifx\@firstpagefooter\@empty\else
      \AtPageLowerLeft{\put(70,45){\makebox(0,0)[lb]{%
        \hbox{%
          \makebox[43bp][l]{\raisebox{-1pt}{%
            \ifx\@licensebadge\@empty
              \begingroup\setlength\fboxsep{1.5pt}%
                \colorbox{black}{\color{white}\sffamily\bfseries
                  \fontsize{5.4}{5.8}\selectfont
                  \makebox[38pt][c]{CC\hfill BY}}\endgroup
            \else
              \includegraphics[width=43bp]{\@licensebadge}%
            \fi}}%
          \hskip4.8bp
          \parbox{293pt}{\fontsize{6.4}{7.4}\selectfont\color{tnqgray}%
            \@firstpagefooter}}}}}%
    \fi
  \fi}
\AddToShipoutPictureBG{\tnq@rules}

\def\tnq@buildheader{%
  \global\setbox\tnq@header\vbox{%
    \hsize\textwidth
    \offinterlineskip
    \hb@xt@\textwidth{%
      \hskip\tnq@firstleftindent
      \vbox to48pt{%
        \ifx\@journallogo\@empty
          \hbox to223pt{%
            \raisebox{-2pt}[43pt][2pt]{\makebox[50pt][c]{%
              \ooalign{%
                \hfil\textcolor{tnqcyan}{\tnqsymbolfont
                  \fontsize{48}{48}\selectfont ○}\hfil\cr
                \hfil\textcolor{tnqcyan}{\sffamily\fontsize{14}{14}\selectfont P}\hfil\cr}}}%
            \hskip17pt
            \vbox{%
              \hbox{\color{tnqblue}\sffamily\bfseries
                \fontsize{28}{28}\selectfont\@journalwordmark}%
              \vskip1pt
              \hbox{\color{tnqblue}\sffamily\mdseries
                \fontsize{9.2}{9.6}\selectfont\@journalsubtitle}}%
            \hfil}%
        \else
          \vskip-1.2pt
          \hbox{\hskip3.7pt\includegraphics[width=196.8bp]{\@journallogo}}%
        \fi
        \vss
      }%
      \hfil
      \vbox to48pt{%
        \vskip-3.9pt
        \hsize165pt
        \raggedleft\tnqmetafont
        {\bfseries\fontsize{8.8}{11}\selectfont\@articletype\par}\vskip.5pt
        {\fontsize{8.2}{13.4}\selectfont\@journalsection\par}\vskip1.5pt
        {\bfseries\fontsize{7.8}{13.4}\selectfont\@articlemeta\par}\vskip1pt
        {\fontsize{8}{13.4}\selectfont DOI: \@doi\par}%
        \vss
      }%
    }%
    \vskip26pt
    \hb@xt@\textwidth{%
      \hskip\tnq@firstleftindent
      \vbox{%
        \hsize318pt
        \parindent\z@\raggedright
        \color{tnqtext}\sffamily\bfseries\fontsize{15}{18}\selectfont
        \baselineskip18pt\lineskiplimit\z@\lineskip1pt
        \@title\par}%
      \hfil}%
    \vskip22pt
  }%
  \global\tnq@available\dimexpr
    \textheight-\ht\tnq@header-\dp\tnq@header-
    \tnq@footerreserve\relax
  \ifdim\tnq@available<2\baselineskip
    \ClassError{tnqjournal}{The page-1 masthead and title leave no body room}%
      {Shorten the title or adjust the journal geometry.}%
  \fi
}

\def\tnq@buildstub{%
  \global\setbox\tnq@stub\vbox{%
    \hsize\tnq@stubwidth
    \linewidth\tnq@stubwidth
    \parindent\z@ \parskip3pt
    \vskip\tnq@stuboffset
    \raggedright\leftskip3pt
    \fontsize{9}{12}\selectfont
    \@authorstub\par
  }%
}

\def\tnq@emitabstract{%
  \begingroup
    % Native hsize is the fallback if page 1 commits while this macro is still
    % emitting a very long abstract.  While state=FIRST_BUILDING, the paragraph
    % hook supplies the measured 344pt leading shape explicitly.
    \hsize\columnwidth
    \linewidth\columnwidth
    \parindent\z@ \parskip9pt plus .6pt minus .4pt
    \fontsize{9}{11}\selectfont\justifying\parindent\z@
    \leftskip11.6pt \rightskip11.6pt
    \let\tnq@abstract@textbf\textbf
    \def\textbf##1{\textcolor{tnqblue}{\tnq@abstract@textbf{##1}}}%
    \directlua{tnqjournal.set_abstract_mode(true)}%
    \hrule height0pt width0pt
  \vskip-5pt
    \noindent{\sffamily\bfseries\color{tnqblue}%
      \fontsize{9.8}{11}\selectfont ABSTRACT}\par
    \@abstracttext\par
    \noindent{\bfseries\color{tnqblue}Keywords: }\@keywords\par
    \directlua{tnqjournal.set_abstract_mode(false)}%
    \vskip9pt
    \vskip17pt
  \endgroup
}

\def\tnq@splitstubfirst{%
  \global\setbox\tnq@stubwork\copy\tnq@stub
  \@tempdima\dimexpr\tnq@available+\tnq@footerreserve+20pt\relax
  \dimen@\dimexpr\ht\tnq@stub+\dp\tnq@stub\relax
  \ifdim\dimen@>\@tempdima
    \global\setbox\tnq@stubpage\vsplit\tnq@stubwork to\@tempdima
  \else
    \global\setbox\tnq@stubpage\vbox{\unvcopy\tnq@stub}%
    \global\setbox\tnq@stubwork\box\voidb@x
  \fi
}

\def\tnq@splitmain{%
  \global\setbox\tnq@mainwork\copy\@cclv
  \global\setbox\tnq@mainpage\vsplit\tnq@mainwork
    to\tnq@mainsplittarget
  \directlua{tnqjournal.prepare_width_split(
    \number\tnq@mainpage,\number\tnq@mainwork)}%
  \ifnum\tnq@widthadjust>\z@
    \ifnum\tnq@splitretries<32
      % Move the target only enough to select the preceding legal line break.
      % A full-baseline jump can skip a heading and strand wide lines in the
      % native tail; one-point retries keep preparation monotonic and bounded.
      \global\advance\tnq@mainsplittarget-1pt
      \global\advance\tnq@splitretries\@ne
      \expandafter\tnq@splitmain
    \fi
  \fi
}

\def\tnq@firstoutput{%
  \vbadness\@M
  \directlua{tnqjournal.suspend_decoration(true)}%
  \global\tnq@savedoutputpenalty\outputpenalty
  % A transition-zone penalty belongs to the one-shot controller, not to the
  % article stream.  It may trigger acquisition, but must not be restored after
  % the semantic tail or it would force an empty/short native left column.
  \iftnq@transitionpending
    \ifnum\tnq@savedoutputpenalty=-\@M
      \global\tnq@savedoutputpenalty\@M
    \fi
    \global\tnq@transitionpendingfalse
  \fi
  \global\tnq@mainsplittarget\tnq@available
  \global\tnq@splitretries\z@
  \directlua{tnqjournal.prepare_payload(
    \number\@cclv,\number\tnq@stub)}%
  \tnq@splitmain
  \directlua{tnqjournal.rehome_marks(
    \number\tnq@mainpage,\number\tnq@mainwork)}%
  \tnq@splitstubfirst
  \directlua{tnqjournal.validate_first_page(
    \number\@cclv,\number\tnq@mainpage,\number\tnq@mainwork,
    \number\tnq@stub,\number\tnq@stubpage,\number\tnq@stubwork)}%
  \ifnum\tnq@validate=\@ne
    % The kernel normally assembles LaTeX's mark-class structures in \@opcol.
    % This one-shot routine bypasses \@opcol, so update them explicitly from
    % the committed article fragment only.  Author-stub marks are outside the
    % article stream and therefore cannot take ownership of a running head.
    \global\setbox\@outputbox\copy\tnq@mainpage
    \@expl@@@mark@update@singlecol@structures@@
    \global\setbox\@outputbox\vbox to\textheight{%
      \box\tnq@header
      \nointerlineskip
      \hb@xt@\textwidth{%
        \hskip\tnq@firstleftindent
        \vbox to\tnq@available{\hsize\tnq@firstmainwidth
          \box\tnq@mainpage\vss}%
        \hskip\tnq@firstgutter
        \vbox to\tnq@available{\hsize\tnq@stubwidth
          \box\tnq@stubpage\vss}%
      }%
      \normalcolor
      \vss
    }%
    % Commit: the originals have remained untouched until this point.
    \global\setbox\@cclv\box\voidb@x
    \global\setbox\tnq@stub\box\tnq@stubwork
    \ifvoid\tnq@mainwork\else
      \unvbox\tnq@mainwork
      \ifnum\tnq@savedoutputpenalty<\@M
        \penalty\tnq@savedoutputpenalty
      \fi
    \fi
    \global\output{\tnq@wrappednativeoutput}%
    \global\tnq@state\tw@
    \global\tnq@transactionarmedfalse
    \global\@firstcolumntrue
    \global\@colht\textheight
    \global\@colroom\textheight
    \global\vsize\textheight
    \@outputpage
    % The published continuation template places native running matter and
    % both columns lower than the special first-page masthead. Keep the footer
    % fixed by reducing text height by the same amount as the top shift.
    \global\advance\topmargin\tnq@nativeshift
    \global\advance\textheight-\tnq@nativeshift
    \global\headsep13pt
    \global\@colht\textheight
    \global\@colroom\textheight
    \global\vsize\textheight
    \directlua{tnqjournal.suspend_decoration(false)}%
    \directlua{tnqjournal.report_commit(tex.box[\number\tnq@stub] ~= nil)}%
    \@floatplacement
  \else
    % Rollback: discard only transaction-owned copies and put the untouched
    % original page list back ahead of contributions.  The error is fatal in
    % the supported automated build, but nonstop mode still cannot commit it.
    \global\setbox\tnq@mainwork\box\voidb@x
    \global\setbox\tnq@mainpage\box\voidb@x
    \global\setbox\tnq@stubwork\box\voidb@x
    \global\setbox\tnq@stubpage\box\voidb@x
    \directlua{tnqjournal.verify_rollback(
      \number\@cclv,\number\tnq@stub)}%
    \unvbox\@cclv
    \ifnum\tnq@savedoutputpenalty<\@M
      \penalty\tnq@savedoutputpenalty
    \fi
    \global\output{\tnq@wrappednativeoutput}%
    \global\tnq@state\thr@@
    \global\tnq@transactionarmedfalse
    \global\@firstcolumntrue
    \global\@colht\textheight
    \global\@colroom\textheight
    \global\vsize\textheight
    \directlua{tnqjournal.suspend_decoration(false)}%
    \ClassError{tnqjournal}{Page-1 transaction accounting failed}%
      {The original page was not committed. Inspect TNQ-ACCOUNT diagnostics.}%
  \fi
}

% Preserve the kernel two-column assembler. While a stub remainder is pending,
% only the right column goal and box prefix are changed.
\let\tnq@kernel@outputdblcol\@outputdblcol

\def\tnq@stage@stub{%
  \vbadness\@M
  \global\tnq@stubstagefalse
  \ifvoid\tnq@stub\else
    \global\tnq@stubmax=.45\textheight
    \global\setbox\tnq@stubtailstage\copy\tnq@stub
    \dimen@\dimexpr\ht\tnq@stub+\dp\tnq@stub\relax
    \ifdim\dimen@>\tnq@stubmax
      \global\setbox\tnq@stubstage\vsplit\tnq@stubtailstage to\tnq@stubmax
      \global\tnq@stubreserve\tnq@stubmax
    \else
      \global\setbox\tnq@stubstage\vbox{\unvcopy\tnq@stub}%
      \global\setbox\tnq@stubtailstage\box\voidb@x
      \global\tnq@stubreserve\dimen@
    \fi
    \global\advance\tnq@stubreserve\baselineskip
    \ifdim\tnq@stubreserve>\dimexpr\textheight-2\baselineskip\relax
      \global\tnq@stubreserve\dimexpr\textheight-2\baselineskip\relax
    \fi
    \global\tnq@stubstagetrue
  \fi
}

\def\tnq@commit@stubstage{%
  \directlua{tnqjournal.validate_stub(
    \number\tnq@stub,\number\tnq@stubstage,\number\tnq@stubtailstage)}%
  \ifnum\tnq@validate=\@ne
    \global\setbox\tnq@stub\box\tnq@stubtailstage
  \else
    \global\setbox\tnq@stubstage\box\voidb@x
    \global\setbox\tnq@stubtailstage\box\voidb@x
    \global\tnq@state\thr@@
    \ClassError{tnqjournal}{Author-stub continuation accounting failed}%
      {The staged continuation was not committed.}%
  \fi
}

\def\@outputdblcol{%
  \ifnum\tnq@state=\tw@
    \if@firstcolumn
      \tnq@stage@stub
      \tnq@kernel@outputdblcol
      \iftnq@stubstage
        \global\@colht\dimexpr\textheight-\tnq@stubreserve\relax
      \fi
    \else
      \iftnq@stubstage
        \tnq@commit@stubstage
        \global\setbox\@outputbox\vbox to\textheight{%
          \hbox to\columnwidth{\hfil\box\tnq@stubstage}%
          \vskip\baselineskip
          \unvbox\@outputbox
          \vss
        }%
        \global\@colht\textheight
        \global\tnq@stubstagefalse
      \fi
      \tnq@kernel@outputdblcol
    \fi
  \else
    \tnq@kernel@outputdblcol
  \fi
}

\renewcommand\maketitle{%
  \ifnum\tnq@state=\z@\else
    \ClassError{tnqjournal}{\string\maketitle may only be used once}{}%
  \fi
  \global\tnq@transactionarmedtrue
  \par
  \thispagestyle{tnqfirst}%
  \tnq@buildheader
  \tnq@buildstub
  \directlua{tnqjournal.set_widths(
    \number\tnq@firstmainwidth,\number\columnwidth)}%
  \global\tnq@nativeoutput\expandafter{\the\output}%
  \global\output{\tnq@firstoutput}%
  \global\tnq@state\@ne
  \global\vsize\textheight
  \directlua{tnqjournal.report_start(\number\tnq@available)}%
  \tnq@emitabstract
}

\def\tnq@drainstub{%
  \vbadness\@M
  \ifvoid\tnq@stub
    \let\tnq@next\relax
  \else
    \ifnum\tnq@draincycles>100
      \ClassError{tnqjournal}{Author-stub continuation did not make progress}{}%
      \let\tnq@next\relax
    \else
      \global\advance\tnq@draincycles\@ne
      \par\null\newpage\null\newpage
      \let\tnq@next\tnq@drainstub
    \fi
  \fi
  \tnq@next
}

\AtEndDocument{%
  % The first page can still be pending for a short article. Commit it before
  % checking whether the independently owned stub has a remainder.
  \clearpage
  \ifnum\tnq@state=\tw@
    \global\tnq@draincycles\z@
    \tnq@drainstub
    \clearpage
  \fi
}
\AddToHook{enddocument/afterlastpage}{\directlua{tnqjournal.report_end()}}

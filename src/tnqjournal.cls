\NeedsTeXFormat{LaTeX2e}[2023-11-01]
\ProvidesClass{tnqjournal}[2026/07/13 v0.2 automatic journal baseline]
\LoadClass[10pt,twocolumn]{article}
\RequirePackage{iftex}
\ifLuaTeX\else\ClassError{tnqjournal}{LuaLaTeX is required}{}\fi
\RequirePackage{lmodern}
\RequirePackage{xcolor}
\RequirePackage{graphicx}
\RequirePackage{ragged2e}
\RequirePackage{eso-pic}
\RequirePackage{geometry}
\RequirePackage{microtype}
\RequirePackage{titlesec}
\RequirePackage{fancyhdr}

\definecolor{tnqblue}{HTML}{0C4A72}
\definecolor{tnqlight}{HTML}{EAF4F8}
\geometry{paperwidth=609.12bp,paperheight=793.92bp,left=52pt,right=36pt,top=42pt,bottom=46pt}
\setlength\columnsep{24pt}
\setlength\parindent{12pt}
\setlength\parskip{0pt}
\pagestyle{fancy}\fancyhf{}\fancyfoot[R]{\sffamily\bfseries\thepage}\renewcommand\headrulewidth{0pt}

\newcommand\journalname[1]{\gdef\@journalname{#1}}
\newcommand\articlemeta[1]{\gdef\@articlemeta{#1}}
\newcommand\abstracttext[1]{\gdef\@abstracttext{#1}}
\newcommand\keywords[1]{\gdef\@keywords{#1}}
\newcommand\authorstub[1]{\gdef\@authorstub{#1}}
\journalname{Utility Policy}\articlemeta{Research Article}\abstracttext{}\keywords{}\authorstub{}

\titleformat{\section}{\sffamily\bfseries\color{tnqblue}\large}{\thesection}{.6em}{}
\titlespacing*{\section}{0pt}{12pt}{5pt}
\titleformat{\subsection}{\sffamily\bfseries\color{tnqblue}}{\thesubsection}{.6em}{}
\titlespacing*{\subsection}{0pt}{9pt}{4pt}

\directlua{tnqjournal = dofile(kpse.find_file('tnqjournal.lua'))}

\newcommand\tnq@rules{%
  \ifnum\value{page}=1\relax
    \AtPageLowerLeft{\color{tnqblue}\put(45,0){\rule{2.2pt}{673pt}}\put(45,704){\rule{2.2pt}{90pt}}}%
  \fi}
\AddToShipoutPictureBG{\tnq@rules}

\renewcommand\maketitle{%
  \directlua{tnqjournal.report_start()}%
  \twocolumn[{%
    \begin{minipage}{\textwidth}
      \sffamily\color{tnqblue}\bfseries\fontsize{24}{25}\selectfont \@journalname\par
      \vspace{4pt}{\scriptsize\bfseries\@articlemeta\par}
      \vspace{22pt}
      {\fontsize{20}{23}\selectfont\bfseries\color{black}\@title\par}
      \vspace{14pt}
      \noindent\hbox to \textwidth{%
        \vtop{\hsize=.68\textwidth
          \colorbox{tnqlight}{\parbox{\dimexpr\hsize-2\fboxsep\relax}{%
            \vspace{5pt}\sffamily\small\justifying
            {\bfseries\color{tnqblue}Abstract}\par\vspace{3pt}
            \@abstracttext\par\vspace{7pt}
            {\bfseries\color{tnqblue}Keywords: }\@keywords\vspace{5pt}}}}%
        \hfill
        \vtop{\hsize=.26\textwidth\raggedright\sffamily\footnotesize\color{tnqblue}\@authorstub}%
      }%
      \vspace{12pt}
    \end{minipage}%
  }]%
}
\AtEndDocument{\directlua{tnqjournal.report_end()}}

using CSV
using DataFrames
using Dates
import Markdown:
    Header,
    parse,
    plain
using NoteMate

csl_path = "/home/cedarprince/.pandoc/ieee.csl"
bibtex_path = "/home/src/Knowledgebase/Zettelkasten/zettel.bib"
note_path = "/home/src/Projects/NewWebSite/notes"

zettelkasten = "/home/src/Knowledgebase/ZK/"

notes = filter(x -> splitext(x)[2] == ".md", readdir(zettelkasten))
filter!(x -> !(contains(x, "meeting") || contains(x, "reflection") || contains(x, "wn")) && length(x) > 14, notes)

blacklist_files = [
    "07072022212638-category-theory-mathema.md",
    "08052022170406-noemie-columbia-studies.md",
    "08122020234400-history-neuroscience.md",
    "09132021013942-correspondences.md",
    "09282022204104-fairness-chat.md",
    "10182020030856-neuriviz-research-notes.md",
    "11032020210222-neuriviz-notes.md",
    "12122022150845-chat-homan-sexism.md",
    "12202022211411-tobal-sora-lab.md"
]

notes = setdiff(notes, blacklist_files)

if !ispath("/home/src/Projects/NewWebSite/scripts/note_records.csv")
    open("/home/src/Projects/NewWebSite/scripts/note_records.csv", "w") do f
        write(f, "filename,title,keywords,summary,creation_date,edit_time\n")
    end
end

records = CSV.read("/home/src/Projects/NewWebSite/scripts/note_records.csv", DataFrame)

authors = CSV.read("/home/src/Projects/NewWebSite/scripts/authorship_records.csv", DataFrame)

for zettel in notes

    file = read(zettelkasten * zettel, String)
    last_edit_time = unix2datetime(mtime(zettelkasten * zettel))

    records_note_info = filter(row -> row.filename == zettel, records)

    # if the note is entirely new or the last time edited on file system does not match recorded last edit
    if isempty(records_note_info) || last_edit_time != first(records_note_info.edit_time)
        # parse the file
        try

            citation_keys = find_citation_groups(file) # the citation format is [@sevorisdoe; @jacobzelko] or [@somebody], BetterBibTex citation key
            inline_citations_dict = create_inline_citations(citation_keys, bibtex_path, csl_path)  # For IEEE, the mapping would be [@sevorisdoe; @jacobzelko] => [1, 2]
            file = replace(file, inline_citations_dict...)

            markdown_links = find_markdown_links(file, group_links = true) # undestands [Another note](othernote.md) format link only?
            relative_links_dict = create_relative_links(markdown_links["relative_links"]; prefix="https://jacobzelko.com/")
            file = replace(file, relative_links_dict...)

            parsed_file = parse(file)

            file_headers = get_headers(parsed_file.content)
            title_header = filter(x -> typeof(x) <: Header{1}, file_headers)
            section_headers = filter(x -> typeof(x) <: Header{2}, file_headers)

            sections = get_sections(parsed_file.content, section_headers; name_sections=true)
            title_section = get_title_section(parsed_file.content, title_header; name_sections=true)
            references_section = create_references(citation_keys, bibtex_path, csl_path)
            file_sections = merge!(sections, title_section)
            file_sections["References"] = (file_sections["References"][1] |> plain) * "\n" * references_section |> parse |> x -> x.content

            title_section = file_sections["Title"]
            bibliography_section = file_sections["Bibliography"][2] |> plain
            notes_section = file_sections["Notes"][2:end] |> plain
            references_section = file_sections["References"] |> plain

            title = title_section[1].text[1] |> x -> replace(x, "\"" => "'")
            date = title_section[2].content[2] |> strip
            summary = title_section[3].content[2] |> strip |> x -> replace(x, "\"" => "'")
            keywords = title_section[4].content[2] |> strip

            if !ismissing(keywords) && occursin("archive", keywords)

                # store known information in NoteMate struct
                note = Note(title, date, summary, keywords, bibliography_section, references_section, notes_section, basename(zettel), zettelkasten * zettel, csl_path, bibtex_path)

                # begin parse to target representation
                # in this case, Franklin markdown
                franklin_note = create_franklin_note(note)


                page = ""
                page = page * generate_franklin_template(title=franklin_note.title, slug=franklin_note.slug, tags=franklin_note.tags, description=franklin_note.description, rss_title=franklin_note.rss_title, rss_description=franklin_note.rss_description, rss_pubdate=franklin_note.rss_pubdate)


                page = page * generate_note_summary(franklin_note)
                page = page * generate_bibliography(franklin_note)
                page = page * generate_table_of_contents()
                page = page * franklin_note.notes
                page = page * generate_citation(franklin_note; citations = authors)
                page = page * generate_references(franklin_note)
                page = page * generate_comments()

                write("$note_path/$(franklin_note.slug * ".md")", page)

                if isempty(records_note_info)
                    push!(records, [zettel, title, keywords, summary, date, last_edit_time], promote=true)
                else
                    filter!(row -> zettel != row.filename, records)
                    push!(records, [zettel, title, keywords, summary, date, last_edit_time], promote=true)
                end
            end

        catch e

            println("Error converting $(zettel)\n")
            println(string(e))
            println("\n\n")

        end
    end
end

d_f = dateformat"U d Y"

undated = filter(row -> !isa(row.creation_date, DateTime), records)
dated = filter(row -> isa(row.creation_date, DateTime), records)
undated.creation_date = DateTime.(undated.creation_date, d_f)

records = vcat(dated, undated)
records.creation_date = DateTime.(records.creation_date)

CSV.write("/home/src/Projects/NewWebSite/scripts/note_records.csv", records)
